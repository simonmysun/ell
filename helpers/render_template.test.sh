#!/usr/bin/env bash

# Self-checking tests for helpers/render_template.sh.
#
# render_template replaced an `eval "cat <<EOF ... EOF"` that ran template
# contents (and interpolated USER_PROMPT / SHELL_CONTEXT) through the shell,
# which was arbitrary code execution. render_template must substitute only the
# allowlisted ${VAR} placeholders as literal data, never evaluating $(...),
# backticks or arithmetic, and must leave unknown placeholders untouched.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";
. "${DIR}/render_template.sh";

echo "render_template tests";
echo "=====================";

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

# Basic substitution of every allowlisted placeholder.
tmpl="${WORK}/basic.json";
printf '{"m":"${ELL_LLM_MODEL}","t":${ELL_LLM_TEMPERATURE},"n":${ELL_LLM_MAX_TOKENS},"s":${ELL_API_STREAM},"p":"${USER_PROMPT}","c":"${SHELL_CONTEXT}"}\n' > "${tmpl}";
out="$(
  ELL_LLM_MODEL=gpt-4o ELL_LLM_TEMPERATURE=0.6 ELL_LLM_MAX_TOKENS=4096 \
  ELL_API_STREAM=false USER_PROMPT=hi SHELL_CONTEXT=ctx \
  render_template "${tmpl}";
)";
assert_equals "all placeholders substituted" \
  '{"m":"gpt-4o","t":0.6,"n":4096,"s":false,"p":"hi","c":"ctx"}' "${out}";

# A command substitution in USER_PROMPT must be kept literal, not executed.
MARKER="${WORK}/pwned";
tmpl2="${WORK}/inject.json";
printf '{"p":"${USER_PROMPT}"}\n' > "${tmpl2}";
out="$(
  USER_PROMPT="a \$(touch '${MARKER}') b" render_template "${tmpl2}";
)";
assert_success   "prompt injection is not executed" test ! -e "${MARKER}";
assert_contains  "prompt injection kept literal" "${out}" '$(touch';

# Backticks and arithmetic in a template body are not evaluated either.
tmpl3="${WORK}/literal.json";
printf '{"x":"`id`","y":"$((1+1))","z":"${USER_PROMPT}"}\n' > "${tmpl3}";
out="$(USER_PROMPT=ok render_template "${tmpl3}")";
assert_contains "backticks left literal"   "${out}" '`id`';
assert_contains "arithmetic left literal"  "${out}" '$((1+1))';
assert_contains "known placeholder still substituted" "${out}" '"z":"ok"';

# An unknown placeholder is left untouched (not evaluated, not blanked).
tmpl4="${WORK}/unknown.json";
printf '{"u":"${SOME_UNKNOWN_VAR}"}\n' > "${tmpl4}";
out="$(SOME_UNKNOWN_VAR=leaked render_template "${tmpl4}")";
assert_equals "unknown placeholder is left verbatim" '{"u":"${SOME_UNKNOWN_VAR}"}' "${out}";

# An empty variable substitutes to nothing (valid for e.g. empty SHELL_CONTEXT).
tmpl5="${WORK}/empty.json";
printf '{"c":"${SHELL_CONTEXT}"}\n' > "${tmpl5}";
out="$(SHELL_CONTEXT="" render_template "${tmpl5}")";
assert_equals "empty value substitutes to empty string" '{"c":""}' "${out}";

# A missing template file returns non-zero.
assert_failure "missing template returns non-zero" render_template "${WORK}/nope.json";

assert_summary;
