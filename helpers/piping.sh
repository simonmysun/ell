#!/usr/bin/env bash

# this function pipes an array of commands together
# e.g. `piping "cat" "grep -v 'foo'" "sort"`

piping() {
  local pipes="" stage sep="";
  if [ ${#} -eq 0 ] || [ "${1}" = '' ]; then
    # logging_debug "No pipes";
    cat -;
  else
    # logging_debug "Piping: ${@}";
    # Each argument is one pipeline stage joined with " | " and run via bash -c.
    # A stage may be a shell command fragment with its own arguments (e.g.
    # "tr a-z A-Z"), so stages are NOT blindly quoted. But a plugin-hook stage is
    # a bare executable PATH that can contain spaces (list_plugin_hooks supports
    # that); left unquoted, bash -c would word-split the path and fail to run it.
    # Detect that case -- a stage that is itself an existing executable file --
    # and shell-quote just those, leaving command fragments untouched.
    for stage in "${@}"; do
      if [ -x "${stage}" ] && [ -f "${stage}" ]; then
        stage="$(printf '%q' "${stage}")";
      fi
      pipes="${pipes}${sep}${stage}";
      sep=" | ";
    done
    bash -c "${pipes}";
  fi
}

export -f piping;