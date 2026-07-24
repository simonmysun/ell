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

assert_summary;
