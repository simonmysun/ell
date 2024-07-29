#!/usr/bin/env bash

piping() {
  if [[ ${#} -eq 0 || ${1} == '' ]]; then
    logging_debug "No pipes";
    stdbuf -o0 cat;
  else
    logging_debug "Piping: ${@}";
    pipes=$(printf " | %s" "${@}");
    pipes=${pipes:3};
    bash -c "$pipes";
  fi
}

export -f piping;