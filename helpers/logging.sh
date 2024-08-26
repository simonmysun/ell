#!/usr/bin/env bash

# logging functions
# the logs are written to stderr so that they don't interfere with pipes

[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_RESET="$(printf "\033[0m")" || LOG_STYLE_RESET="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_PUNC="$(printf "\033[0m\033[2m")" || LOG_STYLE_PUNC="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_DEBUG="$(printf "\033[97m\033[1m")" || LOG_STYLE_DEBUG="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_INFO="$(printf "\033[92m\033[1m")" || LOG_STYLE_INFO="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_WARN="$(printf "\033[96m\033[1m")" || LOG_STYLE_WARN="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_ERROR="$(printf "\033[93m\033[1m")" || LOG_STYLE_ERROR="";
[ "x${TO_TTY}" = xtrue ] && LOG_STYLE_FATAL="$(printf "\033[91m\033[1m")" || LOG_STYLE_FATAL="";

logging_debug() {
  if [ "${ELL_LOG_LEVEL}" -ge 5 ]; then
    echo "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") ${LOG_STYLE_DEBUG}DEBUG${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

function logging_warn() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    echo "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") ${LOG_STYLE_WARN}WARN${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

function logging_info() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    printf "%s" "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") " >&2;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 3 ]; then
    echo "${LOG_STYLE_INFO}INFO${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

function logging_error() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    printf "%s" "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") " >&2;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 2 ]; then
    echo "${LOG_STYLE_ERROR}ERROR${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

function logging_fatal() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    printf "%s" "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") " >&2;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 1 ]; then
    echo "${LOG_STYLE_FATAL}FATAL${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

export -f logging_debug logging_info logging_warn logging_error logging_fatal;