#!/usr/bin/env bash

# End-to-end tests for ell.sh's fatal error paths.
#
# ell.sh has several `logging_fatal; exit 1` branches that were never asserted,
# so a regression turning a fatal condition into a silent success (or a hang)
# would go unnoticed. These drive the real ell entrypoint and check both the
# non-zero exit and the specific error message, so each test fails for the right
# reason. Every invocation is wrapped in `timeout` so a hang fails loudly.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

echo "error path tests";
echo "================";

# --- Template not found -----------------------------------------------------
# A template name that resolves to nothing must exit non-zero with a clear
# "Template not found" message, not fall through.
err="$(printf '' | timeout 8 env TO_TTY=false \
  "${DIR}/../ell" --api-style ell_echo -t no_such_template_xyz "hi" 2>&1 >/dev/null)";
status="${?}";
assert_not_equals "template-not-found exits non-zero" "0" "${status}";
assert_contains   "template-not-found reports the cause" "${err}" "Template not found";

# --- Input file not found ---------------------------------------------------
# -f pointing at a missing file must exit non-zero with "Input file not found".
err="$(timeout 8 env TO_TTY=false ELL_TEMPLATE_PATH="${DIR}/../templates/" \
  "${DIR}/../ell" --api-style ell_echo -m gpt-4o -t default-openai \
  -f "${WORK}/missing_input.txt" "hi" 2>&1 >/dev/null)";
status="${?}";
assert_not_equals "input-file-not-found exits non-zero" "0" "${status}";
assert_contains   "input-file-not-found reports the cause" "${err}" "Input file not found";

# --- Empty payload ----------------------------------------------------------
# An empty template renders an empty payload; ell must refuse rather than send
# nothing. Point at a template dir containing an empty template file.
: > "${WORK}/empty.json";
err="$(printf '' | timeout 8 env TO_TTY=false ELL_TEMPLATE_PATH="${WORK}/" \
  "${DIR}/../ell" --api-style ell_echo -t empty "hi" 2>&1 >/dev/null)";
status="${?}";
assert_not_equals "empty-payload exits non-zero" "0" "${status}";
assert_contains   "empty-payload reports the cause" "${err}" "Failed to build request payload";

assert_summary;
