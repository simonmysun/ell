#!/usr/bin/env bash

# Self-checking tests for helpers/logging.sh.
#
# The logging helpers gate each level on ELL_LOG_LEVEL and write to stderr so
# they don't pollute pipes. The message-visibility thresholds are:
#   debug >= 5, info >= 4, warn >= 3, error >= 2, fatal >= 1.
# These tests capture stderr and assert exactly which messages appear at each
# level. TO_TTY=false disables colour codes so comparisons stay simple.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";

export TO_TTY=false;

. "${DIR}/logging.sh";

# emit_all <level>: set ELL_LOG_LEVEL and call every logging function, returning
# everything written to stderr as a single string.
emit_all() {
  export ELL_LOG_LEVEL="${1}";
  # Capture only stderr. The logging helpers write to stderr; we want that on
  # the captured stdout while discarding any real stdout. Using a wrapper block
  # `{ cmd >/dev/null; } 2>&1` makes the ordering unambiguous (see SC2069): the
  # inner redirect sends stdout to /dev/null, then 2>&1 routes stderr to the
  # command substitution's stdout.
  {
    {
      logging_debug "MSG_DEBUG";
      logging_info  "MSG_INFO";
      logging_warn  "MSG_WARN";
      logging_error "MSG_ERROR";
      logging_fatal "MSG_FATAL";
    } >/dev/null;
  } 2>&1;
}

echo "logging tests";
echo "=============";

# Level 5 (debug): everything is visible.
out="$(emit_all 5)";
assert_contains "L5 shows debug" "${out}" "DEBUG MSG_DEBUG";
assert_contains "L5 shows info"  "${out}" "INFO MSG_INFO";
assert_contains "L5 shows warn"  "${out}" "WARN MSG_WARN";
assert_contains "L5 shows error" "${out}" "ERROR MSG_ERROR";
assert_contains "L5 shows fatal" "${out}" "FATAL MSG_FATAL";

# Level 4 (info): debug hidden, info and below visible.
out="$(emit_all 4)";
assert_not_contains "L4 hides debug" "${out}" "DEBUG MSG_DEBUG";
assert_contains     "L4 shows info"  "${out}" "INFO MSG_INFO";
assert_contains     "L4 shows warn"  "${out}" "WARN MSG_WARN";
assert_contains     "L4 shows error" "${out}" "ERROR MSG_ERROR";
assert_contains     "L4 shows fatal" "${out}" "FATAL MSG_FATAL";

# Level 3 (warn): info's message hidden, warn/error/fatal visible.
out="$(emit_all 3)";
assert_not_contains "L3 hides debug"    "${out}" "DEBUG MSG_DEBUG";
assert_not_contains "L3 hides info msg" "${out}" "INFO MSG_INFO";
assert_contains     "L3 shows warn"     "${out}" "WARN MSG_WARN";
assert_contains     "L3 shows error"    "${out}" "ERROR MSG_ERROR";
assert_contains     "L3 shows fatal"    "${out}" "FATAL MSG_FATAL";

# Level 2 (error): warn's message hidden, error/fatal visible.
out="$(emit_all 2)";
assert_not_contains "L2 hides warn msg" "${out}" "WARN MSG_WARN";
assert_contains     "L2 shows error"    "${out}" "ERROR MSG_ERROR";
assert_contains     "L2 shows fatal"    "${out}" "FATAL MSG_FATAL";

# Level 1 (fatal): only fatal's message visible.
out="$(emit_all 1)";
assert_not_contains "L1 hides error msg" "${out}" "ERROR MSG_ERROR";
assert_contains     "L1 shows fatal"     "${out}" "FATAL MSG_FATAL";

# Level 0: nothing is emitted at all.
out="$(emit_all 0)";
assert_equals "L0 silent" "" "${out}";

# Logs must go to stderr, never stdout (so they don't corrupt piped output).
export ELL_LOG_LEVEL=5;
stdout="$(logging_info "ON_STDOUT" 2>/dev/null)";
assert_equals "logs never reach stdout" "" "${stdout}";

assert_summary;
