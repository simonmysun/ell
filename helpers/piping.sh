#!/usr/bin/env bash

# this function pipes an array of commands together
# e.g. `piping "cat" "grep -v 'foo'" "sort"`

piping() {
  local pipes;
  if [ ${#} -eq 0 ] || [ "${1}" = '' ]; then
    # logging_debug "No pipes";
    cat -;
  else
    # logging_debug "Piping: ${@}";
    pipes="$(printf " | %s" "${@}")";
    # Strip the leading " | " (3 chars) with bash parameter expansion rather
    # than forking echo|cut. ell requires bash >= 4.1, so substring expansion
    # is available and is used throughout the codebase.
    pipes="${pipes:3}";
    bash -c "${pipes}";
  fi
}

export -f piping;