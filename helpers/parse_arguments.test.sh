#!/usr/bin/env bash

# Self-checking tests for helpers/parse_arguments.sh.
#
# The focus here is the -O/--option handler, which used to run
#   eval "export ${key}=${value}"
# and was therefore a command-injection hole: `-O 'X=$(cmd)'` executed cmd.
# It also printed the parsed options to stdout, polluting program output.
#
# These tests lock in the fixed behaviour:
#   * arbitrary command substitution / metacharacters in a value are treated as
#     literal data and never executed,
#   * a value may itself contain '=',
#   * malformed entries and invalid variable names are rejected, not assigned,
#   * the parser writes nothing to stdout while handling -O.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";

# parse_arguments logs via logging_* and mutates the environment (export
# USER_PROMPT and various ELL_*). Silence logging and run each scenario in a
# subshell so assignments from one case cannot leak into the next.
ELL_LOG_LEVEL=0;
export ELL_LOG_LEVEL;
. "${DIR}/logging.sh";
. "${DIR}/parse_arguments.sh";

echo "parse_arguments tests";
echo "=====================";

MARKER="${TMPDIR:-/tmp}/ell_parse_args_pwned.$$";
rm -f "${MARKER}";

# Command substitution in a -O value must NOT be executed.
value_x="$(
  parse_arguments -O "X=\$(touch '${MARKER}')" "prompt" >/dev/null 2>&1;
  printf '%s' "${X}";
)";
if [ -e "${MARKER}" ]; then
  _assert_fail "-O value is not executed as a command";
  rm -f "${MARKER}";
else
  _assert_pass "-O value is not executed as a command";
fi
assert_equals "-O value kept verbatim (not evaluated)" '$(touch '"'${MARKER}'"')' "${value_x}";

# Handling -O must not print anything to stdout.
stdout="$(parse_arguments -O 'A=b' "prompt" 2>/dev/null)";
assert_equals "-O produces no stdout" "" "${stdout}";

# A normal KEY=VALUE assignment works.
value_a="$(parse_arguments -O 'A=b' "prompt" >/dev/null 2>&1; printf '%s' "${A}")";
assert_equals "-O assigns a simple value" "b" "${value_a}";

# A single -O may carry several comma-separated pairs.
values_cd="$(parse_arguments -O 'C=d,E=f' "prompt" >/dev/null 2>&1; printf '%s|%s' "${C}" "${E}")";
assert_equals "-O splits comma-separated pairs" "d|f" "${values_cd}";

# The value may itself contain '=' (split on the first '=' only).
value_eq="$(parse_arguments -O 'C=d=e' "prompt" >/dev/null 2>&1; printf '%s' "${C}")";
assert_equals "-O value may contain '='" "d=e" "${value_eq}";

# An invalid variable name must be rejected, not assigned. '1bad' is not a
# legal shell identifier, so it can never appear in the environment; the parser
# must skip it and log an error instead of failing or assigning anything.
bad_env="$(
  ELL_LOG_LEVEL=0 parse_arguments -O '1bad=x' "prompt" >/dev/null 2>&1;
  # If any assignment had leaked, a variable whose name starts with a digit
  # cannot exist, so scan the environment for the offending value instead.
  env | grep -c '=x$' || true;
)";
assert_equals "-O rejects invalid variable name" "0" "${bad_env}";

# The trailing prompt is still captured correctly alongside -O.
prompt="$(parse_arguments -O 'A=b' "hello world" >/dev/null 2>&1; printf '%s' "${USER_PROMPT}")";
assert_equals "prompt captured with -O present" "hello world" "${prompt}";

# --- Missing-argument handling ----------------------------------------------
#
# A value-taking option given with no value used to leave a single argument for
# `shift 2`, which failed and made the while loop spin forever. Each such option
# must instead exit with EX_USAGE (64) and not hang. Every check is wrapped in
# `timeout` so a regression to the infinite loop fails loudly instead of hanging
# the whole suite.
missing_arg_status() {
  # Run parse_arguments with the given args in a subshell, bounded by timeout,
  # and print its exit status. A timeout (124) indicates the infinite-loop
  # regression.
  timeout 5 bash -c '
    set -o posix;
    ELL_LOG_LEVEL=0;
    . "'"${DIR}"'/logging.sh";
    . "'"${DIR}"'/parse_arguments.sh";
    parse_arguments "${@}";
  ' _ "${@}" >/dev/null 2>&1;
  printf '%s' "${?}";
}

for opt in -l -m -T -t -f -o --api-style --api-key --api-url -c -O; do
  st="$(missing_arg_status "${opt}")";
  assert_equals "missing arg for ${opt} exits 64 (no hang)" "64" "${st}";
done

# A value-taking option followed by a valid trailing value still works even when
# it is the last option before the prompt.
model="$(parse_arguments -m gpt-4o "hi" >/dev/null 2>&1; printf '%s' "${ELL_LLM_MODEL}")";
assert_equals "option with value before prompt still parses" "gpt-4o" "${model}";

# --- -r / --record ----------------------------------------------------------

# A single -r sets ELL_RECORD=true and exports it (so a child process sees it).
record_child="$(
  parse_arguments -r "hi" >/dev/null 2>&1;
  bash -c 'printf "%s" "${ELL_RECORD}"';
)";
assert_equals "-r sets and exports ELL_RECORD" "true" "${record_child}";

# The "already enabled" guard must actually fire (it used to be dead code
# because it compared against the literal "xtrue"). When ELL_RECORD is already
# true and -r is given again, parse_arguments must exit non-zero.
(
  export ELL_RECORD=true;
  parse_arguments -r "hi" >/dev/null 2>&1;
);
assert_not_equals "duplicate -r is rejected (guard not dead)" "0" "${?}";

assert_summary;
