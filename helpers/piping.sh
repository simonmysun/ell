#!/usr/bin/env bash

# this function pipes an array of commands together
# e.g. `piping "cat" "grep -v 'foo'" "sort"`

piping() {
  if [ ${#} -eq 0 ] || [ "${1}" = '' ]; then
    # logging_debug "No pipes";
    cat -;
  else
    # logging_debug "Piping: ${@}";
    pipes="$(printf " | %s" "${@}")";
    pipes=$(echo "$pipes" | cut -c 4-);
    bash -c "${pipes}";
  fi
}

export piping;