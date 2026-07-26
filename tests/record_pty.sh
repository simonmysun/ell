#!/usr/bin/env bash

# End-to-end test for record mode over a real PTY -- the actual user scenario.
#
# `ell -r -i` re-execs itself under `script(1)`, which allocates a pseudo
# terminal and records the whole session to a log. The other record tests feed
# a pipe (not a tty) and only check that the inner ell is located; they
# deliberately avoid a PTY. This test drives ell through a genuine PTY using the
# tests/pty_run.py helper (python3's pty module -- no extra system dependency,
# and present on the CI ubuntu/macOS runners) and asserts the real behaviour:
# the interactive session runs, exits cleanly on EOF, and the prompt is captured
# in the record log.
#
# It skips where the pieces are unavailable (no script(1), or no python3), e.g.
# the minimal alpine bash containers, which cannot run record mode at all.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

echo "record PTY tests";
echo "================";

if ! command -v script >/dev/null 2>&1; then
  echo "SKIP: record_pty (script(1) not available)";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi
PY="";
for c in python3 python; do
  command -v "${c}" >/dev/null 2>&1 && { PY="${c}"; break; }
done
if [ -z "${PY}" ]; then
  echo "SKIP: record_pty (python not available for PTY)";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;
LOG="${WORK}/session.log";

# Drive `ell -r -i` inside a real PTY via pty_run.py: type one prompt, then
# Ctrl-D. ELL_OUTPUT_FILE doubles as the record log so we can inspect it. The
# helper prints "CHILD_EXIT=<n>" as its last line; pty_run.py enforces its own
# timeout, so no ell_timeout wrapper is needed.
out="$(
  cd "${DIR}/.." || exit 1;
  TO_TTY=false ELL_TEMPLATE_PATH="${DIR}/../templates/" ELL_OUTPUT_FILE="${LOG}" \
    "${PY}" "${DIR}/pty_run.py" --timeout 15 --input "PTY_RECORD_XYZ" --send-eof -- \
    ./ell --api-style ell_echo -m gpt-4o --api-disable-streaming -r -i 2>&1;
)";

# The child (the record session) exited cleanly on EOF.
assert_contains "record PTY session exits cleanly" "${out}" "CHILD_EXIT=0";

# The session was recorded to the log, including the typed prompt.
if [ -s "${LOG}" ]; then
  _assert_pass "record log is non-empty";
else
  _assert_fail "record log is non-empty";
fi
assert_contains "record log captured the prompt" "$(cat "${LOG}" 2>/dev/null)" "PTY_RECORD_XYZ";

assert_summary;
