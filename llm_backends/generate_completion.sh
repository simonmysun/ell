#!/usr/bin/env bash

# Dispatcher: source the backend implementation selected by ELL_API_STYLE.
#
# ELL_API_STYLE comes from the CLI/config/environment, and it used to be
# interpolated straight into a source path:
#     . "$(dirname ${0})/llm_backends/${ELL_API_STYLE}/generate_completion.sh"
# so a value like "../../tmp/evil" would source an arbitrary file as shell
# code. Validate the style name against a strict allowlist pattern (a single
# path segment of [A-Za-z0-9._-], no slashes and no "." / ".." traversal)
# before using it, and resolve the backend relative to this file's own
# directory rather than the outer script's ${0}.

# Directory that contains this dispatcher and the per-style backend folders.
# Prefer the caller-provided BASE_DIR (ell.sh), fall back to BASH_SOURCE so the
# file is also correct when sourced directly (e.g. from tests).
_ELL_BACKENDS_DIR="${BASE_DIR:-$(dirname "${BASH_SOURCE[0]}")}/llm_backends";

if ! [[ "${ELL_API_STYLE}" =~ ^[A-Za-z0-9._-]+$ ]] \
   || [ "${ELL_API_STYLE}" = "." ] || [ "${ELL_API_STYLE}" = ".." ]; then
  logging_fatal "Invalid ELL_API_STYLE: '${ELL_API_STYLE}' (expected a backend name like 'openai', 'gemini' or 'ell_echo')";
  exit 1;
fi

_ELL_BACKEND_FILE="${_ELL_BACKENDS_DIR}/${ELL_API_STYLE}/generate_completion.sh";
if [ ! -f "${_ELL_BACKEND_FILE}" ]; then
  logging_fatal "Unknown API style '${ELL_API_STYLE}': no backend at ${_ELL_BACKEND_FILE}";
  exit 1;
fi

# shellcheck source=/dev/null
. "${_ELL_BACKEND_FILE}";
