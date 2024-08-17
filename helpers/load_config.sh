#!/usr/bin/env bash

# Configuration loader. 
# Will not overwrite existing variables.
# Will read from $HOME/.ellrc, $PWD/.ellrc, and $ELL_CONFIG

function load_config() {
  logging::debug "Storing current environment";
  current_env=$(declare -p -x | sed -e 's/declare -x /export /');
  set -o allexport;
  if [[ -f "${HOME}/.ellrc" ]]; then
    logging::debug "Loading config from ${HOME}/.ellrc (from \$HOME)";
    source "${HOME}/.ellrc"
  fi

  if [[ -f "${PWD}/.ellrc" ]]; then
    logging::debug "Loading config from ${PWD}/.ellrc (from \$PWD)";
    source "${PWD}/.ellrc"
  fi

  if [[ -z "${ELL_CONFIG}" ]]; then
    logging::debug "ELL_CONFIG is not set";
  else
    if [[ -f "${ELL_CONFIG}" ]]; then
      logging::debug "Loading config from ${ELL_CONFIG}";
      source "${ELL_CONFIG}"
    else
      logging::fatal "Config file ${ELL_CONFIG} not found";
      exit 1;
    fi
  fi
  logging::debug "Restoring environment";
  eval "${current_env}";
  set +o allexport;
}

export -f load_config;