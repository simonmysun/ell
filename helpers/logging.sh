#!/usr/bin/env bash

function logging_debug() {
  if [[ "${ELL_LOG_LEVEL}" -ge 5 ]]; then
    echo "[[$(date +'%Y-%m-%d %H:%M:%S')]] $(basename "${0}") DEBUG: ${@}" >&2
  fi
}

function logging_warn() {
  if [[ "${ELL_LOG_LEVEL}" -ge 4 ]]; then
    echo "[[$(date +'%Y-%m-%d %H:%M:%S')]] $(basename "${0}") WARN: ${@}" >&2
  fi
}

function logging_info() {
  if [[ "${ELL_LOG_LEVEL}" -ge 4 ]]; then
    echo -n "[[$(date +'%Y-%m-%d %H:%M:%S')]] $(basename "${0}") " >&2
  fi
  if [[ "${ELL_LOG_LEVEL}" -ge 3 ]]; then
    echo "INFO: ${@}" >&2
  fi
}

function logging_error() {
  if [[ "${ELL_LOG_LEVEL}" -ge 4 ]]; then
    echo -n "[[$(date +'%Y-%m-%d %H:%M:%S')]] $(basename "${0}") " >&2
  fi
  if [[ "${ELL_LOG_LEVEL}" -ge 2 ]]; then
    echo "ERROR: ${@}" >&2
  fi
}

function logging_fatal() {
  if [[ "${ELL_LOG_LEVEL}" -ge 4 ]]; then
    echo -n "[[$(date +'%Y-%m-%d %H:%M:%S')]] $(basename "${0}") " >&2
  fi
  if [[ "${ELL_LOG_LEVEL}" -ge 1 ]]; then
    echo "FATAL: ${@}" >&2
  fi
}

export -f logging_debug logging_info logging_warn logging_error logging_fatal;