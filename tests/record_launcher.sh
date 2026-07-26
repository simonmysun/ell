#!/usr/bin/env bash

# End-to-end test for record mode locating ell correctly.
#
# Record mode re-execs ell inside `script -c "<cmd>"`. That command used to be a
# bare `ell`, which only works when ell is installed on PATH; running in place
# (./ell.sh) or from an uninstalled checkout failed with "ell: command not
# found". The fix re-execs "${BASE_DIR}/ell" as an absolute, shell-quoted path.
#
# This test drives record+interactive mode from a checkout that is NOT on PATH
# and whose directory contains a space (to also exercise the quoting), and
# asserts the inner ell actually ran (its echoed payload appears) and that no
# "command not found" occurred. It does not assert a clean exit: record mode
# wraps `script`, whose handling of a piped (non-TTY) stdin is a separate issue,
# so the whole thing is bounded by `timeout`.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

REPO_DIR="$(cd "${DIR}/.." && pwd)";

if ! command -v script >/dev/null 2>&1; then
  echo "SKIP: record_launcher (script(1) not available)";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi

echo "record launcher tests";
echo "=====================";

# Copy the checkout into a path containing a space so the launcher path must be
# quoted, and run it without adding it to PATH.
WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;
SPACED="${WORK}/dir with space";
mkdir -p "${SPACED}";
cp -r "${REPO_DIR}/." "${SPACED}/repo" 2>/dev/null;

out_file="${WORK}/rec.out";
err_file="${WORK}/rec.err";

# Build a PATH that keeps the standard tools (script, bash, mktemp, ...) but
# does NOT contain any installed `ell`, so the test actually proves record mode
# does not depend on ell being on PATH. If a stray ell is still reachable the
# test would pass trivially, so assert it is gone first.
SAFE_PATH="";
for d in /usr/bin /bin /usr/sbin /sbin; do
  [ -d "${d}" ] && SAFE_PATH="${SAFE_PATH:+${SAFE_PATH}:}${d}";
done
if PATH="${SAFE_PATH}" command -v ell >/dev/null 2>&1; then
  echo "SKIP: an 'ell' is reachable even on a minimal PATH; cannot isolate";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi

# Feed one prompt then EOF; bound with timeout so the known script+pipe EOF
# behaviour cannot hang the suite. Run with the ell-free PATH.
(
  cd "${SPACED}/repo" || exit 1;
  printf 'RECORD_LAUNCH_XYZ\n' | ell_timeout 12 \
    env PATH="${SAFE_PATH}" ELL_TEMPLATE_PATH="${SPACED}/repo/templates/" \
    ./ell.sh --api-style ell_echo -m gpt-4o --api-disable-streaming -r -i \
    >"${out_file}" 2>"${err_file}";
);

combined="$(cat "${out_file}" "${err_file}" 2>/dev/null)";

# The inner ell must have been located and run: its echoed request payload
# contains the prompt. If record had exec'd a bare `ell` not on PATH, we would
# instead see a "command not found" and no payload.
assert_contains     "record mode located and ran the inner ell" "${combined}" "RECORD_LAUNCH_XYZ";
assert_not_contains "record mode had no command-not-found"       "${combined}" "not found";

assert_summary;
