#!/usr/bin/env bash

# End-to-end tests for interactive mode (ell -i).
#
# Interactive mode reads prompts from stdin in a loop. On EOF (Ctrl-D) it must
# exit cleanly: previously the read had no EOF handling, so at end-of-input the
# loop spun forever emitting empty completions. Every ell invocation here is
# wrapped in `timeout` so a regression to that infinite loop fails the test
# (exit 124) instead of hanging the whole suite.
#
# The ell_echo backend echoes the request body ell built, so feeding prompts on
# stdin lets us confirm each one was processed without any network.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

# Interactive mode normally auto-enables record mode, which re-executes ell
# inside `script`; `script`'s own handling of a piped (non-TTY) stdin is a
# separate matter. What these tests target is the interactive read loop itself
# (the EOF handling we fixed), which is exactly the code path taken by the inner
# ell that `script` runs. To reach that loop directly and deterministically --
# without a pty -- we point ELL_TMP_SHELL_LOG at an existing file so the
# record-mode entry condition (`[ ! -f "${ELL_TMP_SHELL_LOG}" ]`) is false and
# ell goes straight into the interactive loop.
SHELL_LOG="$(mktemp)";
trap 'rm -f "${SHELL_LOG}"' EXIT;

# run_interactive <stdin-text>: feed text to the interactive read loop (bounded
# by a timeout) and print the output.
run_interactive() {
  printf '%s' "${1}" | timeout 10 \
    env ELL_TEMPLATE_PATH="${DIR}/../templates/" TO_TTY=false \
    ELL_TMP_SHELL_LOG="${SHELL_LOG}" \
    "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming -i \
    2>/dev/null;
}

# run_status <stdin-text>: same as run_interactive but returns the exit status
# (discarding output). A status of 124 means timeout, i.e. the infinite-loop
# regression.
run_status() {
  printf '%s' "${1}" | timeout 10 \
    env ELL_TEMPLATE_PATH="${DIR}/../templates/" TO_TTY=false \
    ELL_TMP_SHELL_LOG="${SHELL_LOG}" \
    "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming -i \
    >/dev/null 2>&1;
}

echo "interactive tests";
echo "=================";

# Immediate EOF (empty stdin): must exit cleanly and quickly, not hang.
run_status "";
status="${?}";
assert_equals "immediate EOF exits cleanly (no hang)" "0" "${status}";

# A single prompt then EOF: the prompt is processed, then it exits.
run_status "$(printf 'hello there\n')";
status="${?}";
assert_equals "one prompt then EOF exits 0" "0" "${status}";
out="$(run_interactive "$(printf 'hello there\n')")";
assert_contains "single prompt processed" "${out}" "hello there";

# Multiple prompts then EOF: each is processed, then it exits.
out="$(run_interactive "$(printf 'first prompt\nsecond prompt\n')")";
assert_contains "first prompt processed"  "${out}" "first prompt";
assert_contains "second prompt processed" "${out}" "second prompt";

# A prompt with no trailing newline before EOF still exits (does not hang).
run_status "no newline at end";
status="${?}";
assert_equals "unterminated line then EOF exits (no hang)" "0" "${status}";

assert_summary;
