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

# --- Missing ELL_API_URL preflight ------------------------------------------
# A network backend with no ELL_API_URL must fail early with a clear, actionable
# message rather than an opaque curl error later. Run in an isolated env so the
# developer's own ~/.ellrc / XDG config cannot supply a URL.
err="$(env -i PATH="${PATH}" HOME="${WORK}/empty_home" \
  XDG_CONFIG_HOME="${WORK}/empty_cfg" XDG_DATA_HOME="${WORK}/empty_data" \
  TO_TTY=false ELL_TEMPLATE_PATH="${DIR}/../templates/" \
  timeout 8 "${DIR}/../ell" --api-style openai -m gpt-4o "hi" </dev/null 2>&1 >/dev/null)";
status="${?}";
assert_not_equals "missing ELL_API_URL exits non-zero" "0" "${status}";
assert_contains   "missing ELL_API_URL names the variable" "${err}" "ELL_API_URL is not set";

# The ell_echo backend needs no URL, so the preflight must NOT block it.
echo_status="$(env -i PATH="${PATH}" HOME="${WORK}/empty_home" \
  XDG_CONFIG_HOME="${WORK}/empty_cfg" XDG_DATA_HOME="${WORK}/empty_data" \
  TO_TTY=false ELL_TEMPLATE_PATH="${DIR}/../templates/" \
  timeout 8 "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming "hi" \
  </dev/null >/dev/null 2>&1; printf '%s' "${?}")";
assert_equals "ell_echo is exempt from the URL preflight" "0" "${echo_status}";

assert_summary;
