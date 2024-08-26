#!/usr/bin/env bash

# logging functions
# the logs are written to stderr so that they don't interfere with pipes

[[ ${TO_TTY} == true ]] && LOG_STYLE_RESET="$(echo -ne "\e[0m")" || LOG_STYLE_RESET="";
[[ ${TO_TTY} == true ]] && LOG_STYLE_PUNC="$(echo -ne "\e[0m\e[2m")" || LOG_STYLE_PUNC="";
[[ ${TO_TTY} == true ]] && LOG_STYLE_DEBUG="$(echo -ne "\e[97m\e[1m")" || LOG_STYLE_DEBUG="";
[[ ${TO_TTY} == true ]] && LOG_STYLE_INFO="$(echo -ne "\e[92m\e[1m")" || LOG_STYLE_INFO="";
[[ ${TO_TTY} == true ]] && LOG_STYLE_WARN="$(echo -ne "\e[96m\e[1m")" || LOG_STYLE_WARN="";
[[ ${TO_TTY} == true ]] && LOG_STYLE_ERROR="$(echo -ne "\e[93m\e[1m")" || LOG_STYLE_ERROR="";
[[ ${TO_TTY} == true ]] && LOG_STYLE_FATAL="$(echo -ne "\e[91m\e[1m")" || LOG_STYLE_FATAL="";

function logging_debug() {
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
    echo -n "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") " >&2;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 3 ]; then
    echo "${LOG_STYLE_INFO}INFO${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

function logging_error() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    echo -n "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") " >&2;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 2 ]; then
    echo "${LOG_STYLE_ERROR}ERROR${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

function logging_fatal() {
  if [ "${ELL_LOG_LEVEL}" -ge 4 ]; then
    echo -n "${LOG_STYLE_PUNC}[${LOG_STYLE_RESET}$(date +'%Y-%m-%d %H:%M:%S')${LOG_STYLE_PUNC}]${LOG_STYLE_RESET} $(basename "${0}") " >&2;
  fi
  if [ "${ELL_LOG_LEVEL}" -ge 1 ]; then
    echo "${LOG_STYLE_FATAL}FATAL${LOG_STYLE_RESET} ${*}" >&2;
  fi
}

export -f logging_debug logging_info logging_warn logging_error logging_fatal;