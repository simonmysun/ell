#!/usr/bin/env bash

# Self-checking tests for helpers/render_template.sh.
#
# render_template replaced an `eval "cat <<EOF ... EOF"` that ran template
# contents (and interpolated USER_PROMPT / SHELL_CONTEXT) through the shell,
# which was arbitrary code execution. render_template must substitute only the
# allowlisted ${VAR} placeholders as literal data, never evaluating $(...),
# backticks or arithmetic, and must leave unknown placeholders untouched.
#
# render_template also owns JSON escaping: string placeholders (USER_PROMPT,
# SHELL_CONTEXT, ELL_LLM_MODEL) are escaped so the rendered payload is valid
# JSON even when the value contains quotes, backslashes or newlines; numeric /
# boolean placeholders are inserted verbatim.

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

# --- JSON escaping of string placeholders -----------------------------------
. "${DIR}/json.sh";

# Double quotes in a string value are escaped so the payload stays valid JSON.
tmpl_q="${WORK}/quote.json";
printf '{"p":"${USER_PROMPT}"}\n' > "${tmpl_q}";
out="$(USER_PROMPT='say "hi"' render_template "${tmpl_q}")";
assert_contains "quotes are JSON-escaped" "${out}" '\"hi\"';
assert_success  "payload with quotes is valid JSON" json_is_valid "${out}";

# Backslashes are escaped.
out="$(USER_PROMPT='a\b' render_template "${tmpl_q}")";
assert_contains "backslash is JSON-escaped" "${out}" 'a\\b';
assert_success  "payload with backslash is valid JSON" json_is_valid "${out}";

# Newlines in a value become \n, keeping the JSON single-line and valid.
out="$(USER_PROMPT="$(printf 'line1\nline2')" render_template "${tmpl_q}")";
assert_contains "newline becomes \\n" "${out}" 'line1\nline2';
assert_success  "payload with newline is valid JSON" json_is_valid "${out}";

# A value that decodes back to the original round-trips through the parser.
out="$(USER_PROMPT='he said "x" \ y' render_template "${tmpl_q}")";
assert_success "escaped payload parses" json_parse "${out}";
assert_equals  "escaped value round-trips" 'he said "x" \ y' "$(json_get p)";

# Numeric/boolean placeholders are NOT quoted or escaped.
tmpl_n="${WORK}/num.json";
printf '{"t":${ELL_LLM_TEMPERATURE},"s":${ELL_API_STREAM}}\n' > "${tmpl_n}";
out="$(ELL_LLM_TEMPERATURE=0.6 ELL_API_STREAM=true render_template "${tmpl_n}")";
assert_equals "numeric placeholders inserted verbatim" '{"t":0.6,"s":true}' "${out}";

# --- _json_escape control characters (fast path vs \u-escape scan) ----------
# The short escapes (\b \f \n \r \t) are handled by fast replacements; any other
# C0 control character is \u-escaped by a per-character scan that only runs when
# such a character is present. Cover both branches directly.

# Fast path: plain text with no control chars is returned unchanged.
assert_equals "plain text unchanged" "hello world" "$(_json_escape 'hello world')";

# Short escapes are applied (fast path: no residual C0 remains to scan).
assert_equals "newline -> backslash-n" 'a\nb' "$(_json_escape "$(printf 'a\nb')")";
assert_equals "tab -> backslash-t"     'a\tb' "$(_json_escape "$(printf 'a\tb')")";

# Scan path: a residual C0 control char (0x01) is \u-escaped, and surrounding
# text and short escapes are preserved.
assert_equals "0x01 -> \\u0001"        'a\u0001b' "$(_json_escape "$(printf 'a\x01b')")";
assert_equals "ESC 0x1b -> \\u001b"    'x\u001by' "$(_json_escape "$(printf 'x\x1by')")";
assert_equals "mixed short + \\u"      'a\n\u001bb' "$(_json_escape "$(printf 'a\n\x1bb')")";

# Whatever the path, the result must be valid inside a JSON string.
esc="$(_json_escape "$(printf 'ctrl \x01 and \x1b end')")";
assert_success "escaped control chars form valid JSON" json_is_valid "{\"x\":\"${esc}\"}";

assert_summary;
