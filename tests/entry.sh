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
# curl is a hard dependency of the file:// backend tests (parse_output.sh). On
# the minimal bash:* (alpine) images it is not preinstalled, so install it via
# apk. Do NOT swallow the outcome silently: if curl ends up missing, the backend
# tests fail with nine confusing "produced no output" errors that look like code
# bugs but are really a missing curl. Instead, verify curl is present and fail
# fast with a clear message if it is not.
if ! command -v curl >/dev/null 2>&1; then
  if command -v apk >/dev/null 2>&1; then
    echo "  curl not found; installing via apk...";
    # Show apk's own output so a real install failure (network, CDN) is visible
    # rather than hidden behind 2>/dev/null.
    apk add curl || echo "  apk add curl failed";
  fi
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

run_test() {
  echo "Running test: ${1}";
  bash "${1}";
  status="${?}";
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
run_test tests/templating.sh;
run_test tests/parse_output.sh;
run_test tests/interactive.sh;
run_test tests/output_redirect.sh;
run_test tests/record_launcher.sh;
run_test tests/error_paths.sh;

# Propagate the suite status: fail if any test above failed, so a regression in
# any test fails CI.
exit "${suite_status}";
