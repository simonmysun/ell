#!/usr/bin/env bash

# Shared HTTP helper for the LLM backends.
#
# Centralises curl invocation so every backend gets the same robustness
# treatment instead of hand-rolling `curl --silent ...` four times:
#
#   * connection/overall timeouts, so a stalled server does not hang ell
#     forever (previously there was no timeout at all);
#   * HTTP error handling, so a 401/429/500 becomes a non-zero curl exit
#     (previously curl returned 0 with an error body and the failure only
#     surfaced later as a vague "Unexpected format").
#
# Configuration (all optional, read from the environment):
#   ELL_CONNECT_TIMEOUT  seconds to wait for the TCP/TLS connection (default 10)
#   ELL_MAX_TIME         seconds for the whole transfer; 0 = no limit
#                        (default 0, so long streaming completions are not
#                        killed mid-response)
#   ELL_CURL_EXTRA_OPTS  extra curl options, word-split, for advanced users
#   ELL_CURL_AUTH_HEADER a single HTTP header (e.g. "Authorization: Bearer X")
#                        that must NOT appear on curl's command line. It is fed
#                        to curl through a --config file so the secret is not
#                        visible in `ps` / /proc/<pid>/cmdline.

# Detect whether this curl supports --fail-with-body (curl >= 7.76). It makes
# curl exit non-zero on HTTP >= 400 while still printing the response body, so
# error details (rate-limit messages etc.) remain visible. Older curl falls back
# to --fail, which also exits non-zero but discards the body.
#
# The result is cached so it is probed at most once per process even though the
# value is computed lazily (so tests can stub curl before the first probe).
_ell_curl_fail_opt() {
  if [ -z "${_ELL_CURL_FAIL_OPT:-}" ]; then
    if curl --help all 2>/dev/null | grep -q -- '--fail-with-body'; then
      _ELL_CURL_FAIL_OPT="--fail-with-body";
    else
      _ELL_CURL_FAIL_OPT="--fail";
    fi
  fi
  printf '%s' "${_ELL_CURL_FAIL_OPT}";
}

# ell_curl <url> [extra curl args...]
# Invoke curl with ell's shared options plus any per-call arguments (headers,
# --data-binary, etc.). Reads the request body from stdin when the caller
# passes --data-binary @-. Returns curl's exit status.
#
# If ELL_CURL_AUTH_HEADER is set, that header is passed to curl via a --config
# file (not on the command line), so the credential is not exposed in the
# process table. A temporary config file with 0600 permissions is used and
# removed immediately; it holds only the header line.
ell_curl() {
  local url="${1}";
  shift;
  # Populate the fail-option cache in this (non-subshell) scope so it is probed
  # at most once per process, then read the cached value.
  _ell_curl_fail_opt >/dev/null;
  local -a opts;
  opts=(
    --silent
    --show-error
    "${_ELL_CURL_FAIL_OPT}"
    --connect-timeout "${ELL_CONNECT_TIMEOUT:-10}"
    --max-time "${ELL_MAX_TIME:-0}"
  );
  # Allow advanced users to append arbitrary curl options.
  if [ -n "${ELL_CURL_EXTRA_OPTS}" ]; then
    # Intentional word splitting so ELL_CURL_EXTRA_OPTS can hold several opts.
    # shellcheck disable=SC2206
    opts+=(${ELL_CURL_EXTRA_OPTS});
  fi

  local auth_cfg="" status;
  if [ -n "${ELL_CURL_AUTH_HEADER}" ]; then
    auth_cfg="$(mktemp)" || {
      logging_error "Failed to create temp file for auth header";
      return 1;
    };
    chmod 600 "${auth_cfg}";
    # curl config syntax: header = "NAME: value". Quote and escape the value so
    # a header containing quotes/backslashes is passed intact.
    printf 'header = "%s"\n' "${ELL_CURL_AUTH_HEADER//\"/\\\"}" > "${auth_cfg}";
    opts+=(--config "${auth_cfg}");
  fi

  curl "${url}" "${opts[@]}" "${@}";
  status="${?}";

  if [ -n "${auth_cfg}" ]; then
    rm -f "${auth_cfg}";
  fi
  return "${status}";
}

export -f _ell_curl_fail_opt;
export -f ell_curl;
