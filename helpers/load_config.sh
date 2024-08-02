#!/usr/bin/env bash

function load_config() {
  logging_debug "Storing current environment";
  current_env=$(declare -p -x | sed -e 's/declare -x /export /');
  set -o allexport;
  if [[ -f "${HOME}/.ellrc" ]]; then
    logging_debug "Loading config from ${HOME}/.ellrc (from \$HOME)";
    source "${HOME}/.ellrc"
  fi

  if [[ -f "${PWD}/.ellrc" ]]; then
    logging_debug "Loading config from ${PWD}/.ellrc (from \$PWD)";
    source "${PWD}/.ellrc"
  fi

  if [[ -z "${ELL_CONFIG}" ]]; then
    logging_debug "ELL_CONFIG is not set";
  else
    if [[ -f "${ELL_CONFIG}" ]]; then
      logging_debug "Loading config from ${ELL_CONFIG}";
      source "${ELL_CONFIG}"
    else
      logging_fatal "Config file ${ELL_CONFIG} not found";
      exit 1;
    fi
  fi
  logging_debug "Restoring environment";
  eval "${current_env}";
  set +o allexport;
}

export -f load_config;