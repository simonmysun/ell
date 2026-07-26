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

# Each log line carries a [YYYY-MM-DD HH:MM:SS] timestamp (produced by the bash
# printf %()T builtin rather than a forked `date`).
export ELL_LOG_LEVEL=4;
line="$({ logging_info "TSCHECK" >/dev/null; } 2>&1)";
if printf '%s' "${line}" | grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]'; then
  _assert_pass "log line has a timestamp";
else
  _assert_fail "log line has a timestamp";
  echo "  line: $(_assert_show "${line}")";
fi

# A non-integer ELL_LOG_LEVEL must not break comparisons: it falls back to the
# default (2), so error is shown, info (needs >=4) is not, and no "integer
# expression" error is emitted. The fallback happens when logging.sh is sourced,
# so re-source it in a subshell with a bad value.
bad_out="$(
  export TO_TTY=false ELL_LOG_LEVEL="not-a-number";
  . "${DIR}/logging.sh";
  { logging_error "ERR_AFTER_BAD"; logging_info "INFO_AFTER_BAD"; } >/dev/null 2>&1 \
    || true;
  { logging_error "ERR_AFTER_BAD"; logging_info "INFO_AFTER_BAD"; } 2>&1 >/dev/null;
)";
assert_contains     "invalid log level falls back to 2 (error shown)" "${bad_out}" "ERROR ERR_AFTER_BAD";
assert_not_contains "invalid log level falls back to 2 (info hidden)" "${bad_out}" "INFO_AFTER_BAD";
assert_not_contains "invalid log level does not error" "${bad_out}" "integer expression";

# --- Timestamp prefix is verbose-only (>= 4), by design ---------------------
# The timestamp/prog prefix is intentionally shown only at high verbosity
# (level >= 4): at lower levels error/fatal print a clean "ERROR: ..."/"FATAL:
# ..." message without timestamp noise, which is friendlier for a CLI. These
# tests pin that intended behaviour.
ts_re='\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]';

has_prefix() {
  printf '%s' "${1}" | grep -qE "^${ts_re}";
}

# At level 2 (default), an error message is shown but WITHOUT the prefix.
export ELL_LOG_LEVEL=2;
err2="$({ logging_error "E2"; } 2>&1)";
assert_contains "error message shown at level 2" "${err2}" "ERROR E2";
if has_prefix "${err2}"; then
  _assert_fail "error has no timestamp prefix at level 2";
  echo "  line: $(_assert_show "${err2}")";
else
  _assert_pass "error has no timestamp prefix at level 2";
fi

# At level 4+ the prefix accompanies the message.
export ELL_LOG_LEVEL=4;
err4="$({ logging_error "E4"; } 2>&1)";
assert_contains "error message shown at level 4" "${err4}" "ERROR E4";
if has_prefix "${err4}"; then
  _assert_pass "error carries timestamp prefix at level 4";
else
  _assert_fail "error carries timestamp prefix at level 4";
  echo "  line: $(_assert_show "${err4}")";
fi

assert_summary;
