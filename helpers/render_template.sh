#!/usr/bin/env bash

# Safe template renderer.
#
# Templates are JSON files containing ${VAR} placeholders. They used to be
# rendered with
#     PAYLOAD="$(eval "cat <<EOF
#     $(cat "${ELL_TEMPLATE_FILE}")
#     EOF")"
# which runs the whole template through the shell: any $(...) or backtick in a
# template file (or arriving through USER_PROMPT / SHELL_CONTEXT) was executed
# as code. Installing a third-party template was therefore arbitrary code
# execution.
#
# render_template performs a strict, allowlist-only substitution instead. It
# replaces exactly the placeholders ell defines, using pure bash string
# replacement, so template contents are treated as data and never evaluated.
# Any other ${...} sequence is left untouched.
#
# render_template also owns JSON escaping. String-valued placeholders
# (USER_PROMPT, SHELL_CONTEXT, ELL_LLM_MODEL) are escaped for embedding inside a
# JSON string, so callers pass raw text and never hand-roll `sed` escaping. This
# means input can pass through the redaction/post_input hooks as raw multi-line
# text first (so those hooks work correctly), and only then be escaped here.
# Numeric/boolean placeholders are substituted verbatim so they stay valid JSON.

# Placeholders substituted as JSON string values (escaped).
ELL_TEMPLATE_STRING_VARS=(
  ELL_LLM_MODEL
  SHELL_CONTEXT
  USER_PROMPT
);

# Placeholders substituted verbatim (JSON numbers / booleans).
ELL_TEMPLATE_RAW_VARS=(
  ELL_LLM_TEMPERATURE
  ELL_LLM_MAX_TOKENS
  ELL_API_STREAM
);

# _json_escape <string>
# Print <string> escaped so it can be embedded between the double quotes of a
# JSON string. Handles backslash, double quote, and the C0 control characters
# that JSON requires to be escaped (\b \t \n \f \r and \u00XX for the rest).
# Pure bash: no subprocess is spawned.
_json_escape() {
  local s="${1}" out="" ch rest i code;

  # Escape backslash first, then double quote, so later replacements do not
  # double-escape the backslashes they introduce.
  s="${s//\\/\\\\}";
  s="${s//\"/\\\"}";
  # The common control characters get their short escape form.
  s="${s//$'\b'/\\b}";
  s="${s//$'\f'/\\f}";
  s="${s//$'\n'/\\n}";
  s="${s//$'\r'/\\r}";
  s="${s//$'\t'/\\t}";

  # Any remaining C0 control characters (0x00-0x1F) must be \u-escaped. Scan for
  # them; the fast path is that there are none and we return s unchanged.
  rest="${s}";
  out="";
  while [ -n "${rest}" ]; do
    ch="${rest:0:1}";
    rest="${rest:1}";
    printf -v code '%d' "'${ch}";
    if [ "${code}" -ge 0 ] && [ "${code}" -lt 32 ]; then
      printf -v ch '\\u%04x' "${code}";
    fi
    out="${out}${ch}";
  done
  printf '%s' "${out}";
}

# _ell_replace_literal <haystack> <token> <value>
# Print <haystack> with every literal occurrence of <token> replaced by the
# literal <value>. Implemented with prefix/suffix stripping rather than
# ${haystack//token/value} because that replacement's handling of backslashes
# and quotes in the replacement string differs between bash 4.1, 4.2 and 5.x
# (some versions eat "\\", others treat surrounding quotes literally). This
# split-and-concat approach is byte-exact and identical across all of them.
_ell_replace_literal() {
  local haystack="${1}" token="${2}" value="${3}" out="" rest pre;
  rest="${haystack}";
  while true; do
    pre="${rest%%"${token}"*}";
    if [ "${pre}" = "${rest}" ]; then
      # No further occurrence of the token.
      out="${out}${rest}";
      break;
    fi
    out="${out}${pre}${value}";
    rest="${rest#*"${token}"}";
  done
  printf '%s' "${out}";
}

# render_template <template-file>
# Print the template with the allowlisted ${VAR} placeholders replaced. String
# placeholders are JSON-escaped; numeric/boolean placeholders are inserted
# verbatim. No shell evaluation of the template is performed. Returns non-zero
# if the file cannot be read.
render_template() {
  local template_file="${1}";
  local content var value;

  if [ ! -f "${template_file}" ]; then
    return 1;
  fi

  # Slurp the file verbatim. Command substitution strips trailing newlines,
  # which is fine: the payload is JSON consumed by curl and a trailing newline
  # is irrelevant.
  content="$(cat "${template_file}")";

  # String placeholders: JSON-escape the value before substituting.
  for var in "${ELL_TEMPLATE_STRING_VARS[@]}"; do
    value="$(_json_escape "${!var}")";
    content="$(_ell_replace_literal "${content}" "\${${var}}" "${value}")";
  done

  # Raw placeholders: inserted verbatim so JSON numbers/booleans stay valid.
  for var in "${ELL_TEMPLATE_RAW_VARS[@]}"; do
    value="${!var}";
    content="$(_ell_replace_literal "${content}" "\${${var}}" "${value}")";
  done

  printf '%s\n' "${content}";
}

export -f _json_escape;
export -f _ell_replace_literal;
export -f render_template;
