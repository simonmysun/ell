#!/usr/bin/env bash

# this function pipe an array of commands together
# e.g. piping "cat" "grep -v 'foo'" "sort"

piping() {
  if [[ ${#} -eq 0 || ${1} == '' ]]; then
    # logging::debug "No pipes";
    cat -;
  else
    # logging::debug "Piping: ${@}";
    pipes="$(printf " | %s" "${@}")";
    pipes="${pipes:3}";
    bash -c "${pipes}";
  fi
}

export -f piping;