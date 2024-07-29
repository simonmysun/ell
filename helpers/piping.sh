#!/usr/bin/env bash

piping() {
  if [[ ${#} -eq 0 ]]; then
    logging_debug "No pipes";
    stdbuf -o0 cat;
  else
    pipes=$(printf " | %s" "${@}");
    pipes=${pipes:3};
    bash -c "$pipes";
  fi
}

export -f piping;