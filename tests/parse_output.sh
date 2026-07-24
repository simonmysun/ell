#!/usr/bin/env bash

# Self-checking tests for ell's response parsing across API styles and modes.
#
# ell reads the LLM response from ELL_API_URL. Pointing that at a local
# file:// fixture lets us exercise the real openai/gemini backends and the
# streaming vs non-streaming code paths with deterministic, offline data.
#
# The fixtures live next to this script. Paths are derived from the script's
# own location so the test runs both inside the CI container (mounted at /ell)
# and directly from a checkout.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

# run_ell <style> <model> <stream:true|false>
# Runs `ell test` against the matching fixture and prints the assistant text.
# stderr is discarded so only the parsed output is captured.
run_ell() {
  local style="${1}" model="${2}" stream="${3}" suffix;
  if [ "${stream}" = "true" ]; then suffix=""; else suffix="no-"; fi
  ELL_API_STYLE="${style}" \
  ELL_LLM_MODEL="${model}" \
  ELL_API_STREAM="${stream}" \
  ELL_API_URL="file://${DIR}/${style}-${suffix}stream.json#" \
  ELL_API_KEY="" \
  ELL_TEMPLATE_PATH="${DIR}/../templates/" \
  ELL_TEMPLATE="default-${style}" \
  TO_TTY=false \
    "${DIR}/../ell" test 2>/dev/null;
}

echo "parse_output tests";
echo "==================";

# --- OpenAI ------------------------------------------------------------------

out="$(run_ell openai gpt-4o-mini false)";
assert_not_equals "openai no-stream produced output"  "" "${out}";
assert_contains   "openai no-stream parsed content"   "${out}" "Markdown is a lightweight markup language";
assert_not_contains "openai no-stream leaks no JSON keys" "${out}" '"choices"';
assert_not_contains "openai no-stream leaks no role"     "${out}" '"role"';

out="$(run_ell openai gpt-4o-mini true)";
assert_not_equals "openai stream produced output" "" "${out}";
assert_contains   "openai stream parsed content"  "${out}" "Markdown";
assert_not_contains "openai stream leaks no data: prefix" "${out}" 'data:';

# --- Gemini ------------------------------------------------------------------

out="$(run_ell gemini gemini-1.5-flash false)";
assert_not_equals "gemini no-stream produced output" "" "${out}";
assert_contains   "gemini no-stream parsed content"  "${out}" "Markdown";
assert_not_contains "gemini no-stream leaks no JSON keys" "${out}" '"candidates"';

out="$(run_ell gemini gemini-1.5-flash true)";
assert_not_equals "gemini stream produced output" "" "${out}";
assert_contains   "gemini stream parsed content"  "${out}" "Comprehensive Markdown Guide";
assert_not_contains "gemini stream leaks no parts key" "${out}" '"parts"';

assert_summary;
