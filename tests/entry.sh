#!/usr/bin/env bash

# Container entry point for the test suite.
#
# Works both when the repo is mounted read-only at /ell (via docker.sh) and when
# it is checked out anywhere (e.g. GitHub Actions), by deriving all paths from
# this script's own location instead of hardcoding /ell.
#
# Tests come in two flavours:
#   * Unit tests live next to the source they cover and are named
#     "<source>.test.sh" (e.g. helpers/json.test.sh). They are auto-discovered,
#     so adding one requires no change here.
#   * End-to-end tests that drive the whole ell pipeline (and their JSON
#     fixtures) live in this tests/ directory and are listed explicitly below.

set -o posix;

TESTS_DIR="$(cd "$(dirname "${0}")" && pwd)";
REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)";

echo "Setting up prerequisites...";
# On the minimal bash:* (alpine) images several tools the suite needs are not
# preinstalled. Install them via apk so the container can run the FULL suite
# instead of skipping tests:
#   * curl        - hard dependency of the file:// backend tests (parse_output)
#   * sed         - GNU sed provides `sed -z`, needed by the redaction multiline
#                   test (busybox sed lacks it)
#   * util-linux  - provides script(1), needed by the record-mode tests
#   * python3     - needed by the real-PTY record test (tests/pty_run.py)
# Everything except curl is best-effort: those tests skip cleanly if their tool
# is missing. curl, by contrast, is verified below and is a hard failure, since
# without it the backend tests fail with confusing "produced no output" errors
# that look like code bugs rather than a missing tool.
if command -v apk >/dev/null 2>&1; then
  echo "  Installing test tools via apk (curl, GNU sed, util-linux, python3)...";
  apk add --no-cache curl sed util-linux python3 || echo "  apk add failed (some tests may skip)";
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required to run the test suite (file:// backend tests) but could not be installed." >&2;
  echo "       Install curl and re-run, e.g. 'apk add curl' or 'apt-get install curl'." >&2;
  exit 1;
fi

echo "Installing ell launcher...";
# Install a global `ell` launcher pointing at this checkout. This is best-effort:
# the individual tests invoke ell via a relative path, so the suite still runs
# even if /usr/local/bin is not writable.
if printf '#!/usr/bin/env bash\n\n%s/ell "${@}"\n' "${REPO_DIR}" \
     > /usr/local/bin/ell 2>/dev/null; then
  chmod +x /usr/local/bin/ell;
else
  echo "  (skipped: /usr/local/bin not writable; tests use relative paths)";
fi

cd "${REPO_DIR}" || exit 1;

echo "Running tests...";

# Track the overall suite status. Any test that exits non-zero must fail CI,
# so we remember the first failure instead of letting a later passing test
# mask an earlier regression.
suite_status=0;
# Count skipped checks across all tests. A test prints "SKIP: <reason>" for each
# check it cannot run (a missing tool, not a failure); we tally them so the
# final summary shows how many were skipped rather than leaving them scattered.
suite_skipped=0;
_run_out="$(mktemp 2>/dev/null || echo /tmp/ell_run_out.$$)";

run_test() {
  echo "Running test: ${1}";
  # Capture output to tally SKIP lines while still showing it live via tee.
  bash "${1}" 2>&1 | tee "${_run_out}";
  status="${PIPESTATUS[0]}";
  # `grep -c` prints the count but exits 1 when there are no matches; capture the
  # count and ignore the exit status (a bare number, so arithmetic is safe).
  skipped="$(grep -c '^SKIP:' "${_run_out}" 2>/dev/null)";
  suite_skipped=$(( suite_skipped + skipped ));
  if [ "${status}" -ne 0 ]; then
    echo "Test failed: ${1} (exit ${status})";
    suite_status=1;
  fi;
}

# --- Co-located unit tests (auto-discovered) --------------------------------
# Find every *.test.sh under the repo, excluding the tests/ directory itself
# (which holds shared helpers and the end-to-end tests run below). Sorted for a
# stable, reproducible order.
#
# Process substitution (`< <(...)`) is a bashism that is disabled under
# `set -o posix` on older bash (e.g. 4.1), so we iterate over the find output
# with a plain for-loop and a newline-only IFS instead. Test paths contain no
# whitespace, so word-splitting on newlines is safe here.
unit_tests="$(find . -type f -name '*.test.sh' -not -path './tests/*' 2>/dev/null | sort)";
if [ -n "${unit_tests}" ]; then
  OLD_IFS="${IFS}";
  # Newline-only IFS via ANSI-C quoting rather than a multiline literal, so the
  # value is unambiguously a single newline. A literal would silently absorb any
  # indentation before its closing quote and reintroduce space-splitting; and a
  # $(printf '\n') substitution is wrong here because command substitution strips
  # the trailing newline, leaving IFS empty. $'\n' works under `set -o posix`.
  IFS=$'\n';
  for test_file in ${unit_tests}; do
    run_test "${test_file}";
  done
  IFS="${OLD_IFS}";
fi

# --- End-to-end tests (explicit) --------------------------------------------
# The assertion library's own meta-tests live in tests/ (excluded from unit-test
# auto-discovery), so register them explicitly.
run_test tests/assert_lib.test.sh;
run_test tests/templating.sh;
run_test tests/parse_output.sh;
run_test tests/interactive.sh;
run_test tests/output_redirect.sh;
run_test tests/record_launcher.sh;
run_test tests/record_pty.sh;
run_test tests/error_paths.sh;
run_test tests/launcher.sh;
run_test tests/hooks.sh;
run_test tests/bash_version.sh;
run_test tests/terminal_size.sh;

rm -f "${_run_out}";

# Suite-wide summary. Skipped checks are informational (a tool was unavailable
# in this environment, e.g. GNU sed / script / python in a minimal container),
# not failures.
echo "";
if [ "${suite_skipped}" -gt 0 ]; then
  echo "Suite: ${suite_skipped} check(s) skipped (missing optional tools in this environment).";
else
  echo "Suite: no checks skipped (all tools available).";
fi
if [ "${suite_status}" -eq 0 ]; then
  echo "Suite: all tests passed.";
else
  echo "Suite: one or more tests FAILED.";
fi

# Propagate the suite status: fail if any test above failed, so a regression in
# any test fails CI.
exit "${suite_status}";
