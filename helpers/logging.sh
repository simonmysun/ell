#!/usr/bin/env bash

# logging functions
# the logs are written to stderr so that they don't interfere with pipes

# Default log level. ell.sh sets this to 2 before sourcing this file, so this
# ":-2" only applies when logging.sh is sourced on its own (e.g. in tests). Keep
# both defaults at 2 so the level is the same regardless of entry point.
# Levels: 1 fatal, 2 error, 3 warn, 4 info, 5 debug.
ELL_LOG_LEVEL="${ELL_LOG_LEVEL:-2}";
# ELL_LOG_LEVEL is compared numerically with `-ge`; a non-integer value (e.g.
# from `-l abc`) would make every comparison error out. Fall back to the default
# if it is not a plain non-negative integer.
case "${ELL_LOG_LEVEL}" in
  ''|*[!0-9]*) ELL_LOG_LEVEL=2;;
esac

TO_TTY="${TO_TTY:-true}";

# The program name is constant for the life of the process; compute it once
# instead of forking basename on every log line.
_ELL_LOG_PROG="${0##*/}";

# The printf %()T time format is a bash 4.2 builtin that lets us format the
# timestamp without forking `date`. 
if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] \
   || { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 2 ]; }; then
  # bash >= 4.2: format via the printf %()T builtin, no subprocess.
  _ell_now() {
    printf -v "${1}" '%(%Y-%m-%d %H:%M:%S)T' -1;
  }
else
  # bash 4.1: fall back to forking date.
  _ell_now() {
    printf -v "${1}" '%s' "$(date +'%Y-%m-%d %H:%M:%S')";
  }
fi

[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_RESET="$(printf "\033[0m")" || LOG_STYLE_RESET="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_PUNC="$(printf "\033[0m\033[2m")" || LOG_STYLE_PUNC="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_DEBUG="$(printf "\033[97m\033[1m")" || LOG_STYLE_DEBUG="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_INFO="$(printf "\033[92m\033[1m")" || LOG_STYLE_INFO="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_WARN="$(printf "\033[96m\033[1m")" || LOG_STYLE_WARN="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_ERROR="$(printf "\033[93m\033[1m")" || LOG_STYLE_ERROR="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_FATAL="$(printf "\033[91m\033[1m")" || LOG_STYLE_FATAL="";

# _ell_log_prefix: print "[<timestamp>] <prog> " to stderr. The timestamp
# strategy (_ell_now) was chosen once at load time, so there is no per-call
# version check here.
_ell_log_prefix() {
  local ts;
  _ell_now ts;
  printf "%s" "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}${ts}${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} ${_ELL_LOG_PROG} " >&2;
}

logging_debug() {
  if [ "${ELL_LOG_LEVEL}" -ge 5 ]; then
    _ell_log_prefix;
    echo "${LOG_STYLE_DEBUG}DEBUG${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

logging_info() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    _ell_log_prefix;
    echo "${LOG_STYLE_INFO}INFO${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

logging_warn() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    _ell_log_prefix;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 3 ]; then
    echo "${LOG_STYLE_WARN}WARN${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

logging_error() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    _ell_log_prefix;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 2 ]; then
    echo "${LOG_STYLE_ERROR}ERROR${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

logging_fatal() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    _ell_log_prefix;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 1 ]; then
    echo "${LOG_STYLE_FATAL}FATAL${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

export -f _ell_now _ell_log_prefix logging_debug logging_info logging_warn logging_error logging_fatal;
