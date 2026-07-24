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

# The only placeholders ell substitutes into templates. Keep this in sync with
# the variables referenced by the bundled templates.
ELL_TEMPLATE_VARS=(
  ELL_LLM_MODEL
  ELL_LLM_TEMPERATURE
  ELL_LLM_MAX_TOKENS
  ELL_API_STREAM
  SHELL_CONTEXT
  USER_PROMPT
);

# render_template <template-file>
# Print the template with the allowlisted ${VAR} placeholders replaced by the
# literal values of the corresponding shell variables. No shell evaluation of
# the template is performed. Returns non-zero if the file cannot be read.
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

  # Replace each known placeholder with the literal variable value. Using
  # ${content//"${token}"/${value}} keeps both the search token and the
  # replacement literal (the quoted token disables globbing; the value is not
  # re-parsed), so nothing in the value can be interpreted as code or as
  # another placeholder.
  for var in "${ELL_TEMPLATE_VARS[@]}"; do
    value="${!var}";
    content="${content//"\${${var}}"/${value}}";
  done

  printf '%s\n' "${content}";
}

export -f render_template;
