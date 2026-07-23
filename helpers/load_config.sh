#!/usr/bin/env bash

# Configuration loader. 
# Will not overwrite existing variables.
# Sources configuration files in the following order (later files override
# earlier ones, but never override variables already set in the environment):
#   1. ${XDG_CONFIG_HOME:-$HOME/.config}/ell/config  (XDG main config)
#   2. $HOME/.ellrc                                   (legacy, kept for compat)
#   3. $PWD/.ellrc                                    (per-project config)
#   4. $ELL_CONFIG                                    (explicit override)

load_config() {
  local current_env ELL_XDG_CONFIG;
  logging_debug "Storing current environment";
  current_env=$(declare -p -x | sed -e 's/declare -x /export /');
  set -o allexport;

  ELL_XDG_CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}/ell/config";
  if [ -f "${ELL_XDG_CONFIG}" ]; then
    logging_debug "Loading config from ${ELL_XDG_CONFIG} (XDG)";
    . "${ELL_XDG_CONFIG}"
  fi

  if [ -f "${HOME}/.ellrc" ]; then
    logging_debug "Loading config from ${HOME}/.ellrc (from \$HOME, legacy)";
    . "${HOME}/.ellrc"
  fi

  if [ -f "${PWD}/.ellrc" ]; then
    logging_debug "Loading config from ${PWD}/.ellrc (from \$PWD)";
    . "${PWD}/.ellrc"
  fi

  if [ -z "${ELL_CONFIG}" ]; then
    logging_debug "ELL_CONFIG is not set";
  else
    if [ -f "${ELL_CONFIG}" ]; then
      logging_debug "Loading config from ${ELL_CONFIG}";
      . "${ELL_CONFIG}"
    else
      logging_fatal "Config file ${ELL_CONFIG} not found";
      exit 1;
    fi
  fi
  logging_debug "Restoring environment";
  eval "${current_env}";
  set +o allexport;
}

export load_config;