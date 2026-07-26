#!/usr/bin/env bash

# Configuration loader. 
# Will not overwrite existing variables.
# Sources configuration files in the following order (later files override
# earlier ones, but never override variables already set in the environment):
#   1. ${XDG_CONFIG_HOME:-$HOME/.config}/ell/config  (XDG main config)
#   2. $HOME/.ellrc                                   (legacy, kept for compat)
#   3. $PWD/.ellrc                                    (per-project config)
#   4. $ELL_CONFIG                                    (explicit override)

# _config_is_trusted <file>
# Config files are sourced, i.e. executed as shell code. Only source a file
# that cannot have been planted or tampered with by another user: it must be
# owned by the current user (or root) and must not be writable by its group or
# by others. This closes the "run ell in a directory containing a hostile
# .ellrc" arbitrary-code-execution hole (the $PWD/.ellrc case in particular).
#
# If ownership/permissions cannot be determined (no usable stat), err on the
# side of caution and refuse to source the file.
_config_is_trusted() {
  local file="${1}" owner perms;

  # Owner UID and octal permission bits, trying GNU stat then BSD/macOS stat.
  owner="$(stat -c '%u' "${file}" 2>/dev/null || stat -f '%u' "${file}" 2>/dev/null)";
  perms="$(stat -c '%a' "${file}" 2>/dev/null || stat -f '%Lp' "${file}" 2>/dev/null)";

  # These refusals mean a config file the user created is being ignored, which
  # otherwise looks like "my settings don't work" with no explanation. Report
  # them at error level so they are visible at the default log level (a missing
  # config, by contrast, is silent and normal).
  if [ -z "${owner}" ] || [ -z "${perms}" ]; then
    logging_error "Cannot verify ownership/permissions of ${file}; refusing to source it";
    return 1;
  fi

  # Must be owned by us or by root (root-owned system config is trusted).
  if [ "${owner}" != "$(id -u)" ] && [ "${owner}" != "0" ]; then
    logging_error "Ignoring config ${file}: not owned by the current user or root";
    return 1;
  fi

  # Reject group- or world-writable files. `perms` is an octal string like
  # "644" or "0644"; the last two characters are the group and other digits.
  # Each is a single octal digit, so its write bit is the 2's place.
  local group_bit="${perms: -2:1}" other_bit="${perms: -1:1}";
  if [ "$(( 8#${group_bit:-0} & 2 ))" -ne 0 ] || [ "$(( 8#${other_bit:-0} & 2 ))" -ne 0 ]; then
    logging_error "Ignoring config ${file}: writable by group or others (insecure permissions); run 'chmod 600 ${file}'";
    return 1;
  fi

  return 0;
}

# _load_config_file <file> <description>
# Source a config file only if it exists and passes the trust check.
_load_config_file() {
  local file="${1}" desc="${2}";
  [ -f "${file}" ] || return 0;
  if ! _config_is_trusted "${file}"; then
    return 0;
  fi
  logging_debug "Loading config from ${file}${desc:+ }${desc}";
  # Sourcing a user-provided config path is intentional and dynamic; the trust
  # check above gates it. shellcheck cannot follow a non-constant source.
  # shellcheck disable=SC1090
  . "${file}";
}

load_config() {
  local current_env ELL_XDG_CONFIG;
  logging_debug "Storing current environment";
  current_env=$(declare -p -x | sed -e 's/declare -x /export /');
  set -o allexport;

  ELL_XDG_CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}/ell/config";
  _load_config_file "${ELL_XDG_CONFIG}" "(XDG)";
  _load_config_file "${HOME}/.ellrc" "(from \$HOME, legacy)";
  _load_config_file "${PWD}/.ellrc" "(from \$PWD)";

  if [ -z "${ELL_CONFIG}" ]; then
    logging_debug "ELL_CONFIG is not set";
  else
    if [ -f "${ELL_CONFIG}" ]; then
      _load_config_file "${ELL_CONFIG}" "";
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