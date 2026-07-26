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
#   ELL_ALLOW_INSECURE_URL  set to "true" to permit sending an auth header over
#                        a plaintext http:// URL (otherwise refused, to avoid
#                        leaking the credential in cleartext). Loopback hosts
#                        (localhost/127.0.0.1/::1) are always allowed.

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

# _ell_on_windows: return 0 when running under a Windows bash (Git Bash / MSYS2
# / Cygwin), where filesystem paths are POSIX-style (e.g. /c/Users/...) but the
# native curl expects Windows paths (C:/Users/...). Detected from $OSTYPE, which
# is "msys" for Git Bash, "cygwin" for Cygwin, and "win32" in rare setups.
_ell_on_windows() {
  case "${OSTYPE:-}" in
    msys|cygwin|win32) return 0 ;;
    *) return 1 ;;
  esac
}

# _ell_fixup_file_url <url>: on Windows bash, rewrite a file:// URL whose path is
# a POSIX/MSYS path (/c/Users/... or /tmp/...) into the file:///C:/... form the
# native curl understands, using cygpath. On every other platform, and for any
# non-file:// URL, the input is printed back unchanged. Any optional "#fragment"
# ell appends to force curl's URL parsing is preserved.
_ell_fixup_file_url() {
  local url="${1}" path frag win;
  # Only file:// URLs on Windows bash need fixing; everything else is verbatim.
  if ! _ell_on_windows || ! command -v cygpath >/dev/null 2>&1; then
    printf '%s' "${url}";
    return 0;
  fi
  case "${url}" in
    file://*|FILE://*) ;;
    *) printf '%s' "${url}"; return 0 ;;
  esac
  # Strip the scheme (and an authority-less "//") to get the raw path, then split
  # off any trailing "#fragment" so it is not passed through cygpath.
  path="${url#*://}";
  path="${path#/}";              # tolerate file:///path (leading extra slash)
  case "${path}" in
    *#*) frag="#${path#*#}"; path="${path%%#*}" ;;
    *)   frag="" ;;
  esac
  path="/${path}";              # restore a leading slash for cygpath
  # cygpath -m yields a Windows path with forward slashes (C:/Users/...), which
  # is exactly what a file:// URL wants. If conversion fails, fall back to the
  # original URL rather than emitting something broken.
  win="$(cygpath -m -- "${path}" 2>/dev/null)" || { printf '%s' "${url}"; return 0; };
  if [ -z "${win}" ]; then printf '%s' "${url}"; return 0; fi
  printf 'file:///%s%s' "${win}" "${frag}";
}

# _ell_url_is_secure <url>: return 0 if it is safe to send a credential to
# <url>. https:// and file:// are safe; http:// is only safe for loopback hosts
# (localhost / 127.0.0.1 / ::1). Any other scheme is treated as safe so this
# check only ever blocks the clear risk: an explicit plaintext http:// remote.
_ell_url_is_secure() {
  local url="${1}" host rest;
  case "${url}" in
    https://*|HTTPS://*) return 0 ;;
    file://*|FILE://*)   return 0 ;;
    http://*|HTTP://*)
      # Strip scheme, then take the authority (up to the first '/' or '?').
      rest="${url#*://}";
      host="${rest%%[/?]*}";
      # Split off the port. A bracketed IPv6 authority (e.g. "[::1]:8080")
      # contains ':' inside the brackets, so trim to the closing ']' first and
      # only then drop a trailing ":port"; otherwise strip at the first ':'.
      case "${host}" in
        '['*']'*) host="${host%%]*}]" ;;
        *)        host="${host%%:*}" ;;
      esac
      case "${host}" in
        localhost|127.0.0.1|'[::1]'|::1) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 0 ;;
  esac
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
  # On Windows bash a file:// URL carries a POSIX path the native curl cannot
  # read; rewrite it to file:///C:/... there. A no-op everywhere else.
  url="$(_ell_fixup_file_url "${url}")";
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

  # Refuse to send credentials over a plaintext http:// URL (the key would go
  # out in cleartext). https://, file:// and loopback http hosts are fine, and
  # ELL_ALLOW_INSECURE_URL=true is an explicit opt-out.
  if [ -n "${ELL_CURL_AUTH_HEADER}" ] && ! _ell_url_is_secure "${url}"; then
    if [ "x${ELL_ALLOW_INSECURE_URL}" != "xtrue" ]; then
      logging_fatal "Refusing to send credentials to a non-HTTPS URL: ${url}";
      logging_fatal "Use https://, or set ELL_ALLOW_INSECURE_URL=true to override.";
      return 1;
    fi
    logging_warn "Sending credentials over an insecure URL (ELL_ALLOW_INSECURE_URL=true): ${url}";
  fi

  local auth_cfg="" status _ell_auth_val;
  if [ -n "${ELL_CURL_AUTH_HEADER}" ]; then
    auth_cfg="$(mktemp)" || {
      logging_error "Failed to create temp file for auth header";
      return 1;
    };
    # chmod 600 before writing so the secret is never briefly world-readable.
    chmod 600 "${auth_cfg}";
    # curl config syntax: header = "NAME: value". Inside double quotes curl
    # treats backslash as an escape introducer (\\, \", \t, \n, \r, \v), so a
    # header value must have its backslashes escaped BEFORE its double quotes
    # (escaping quotes first would then double-escape the added backslashes).
    _ell_auth_val="${ELL_CURL_AUTH_HEADER//\\/\\\\}";   # \ -> \\
    _ell_auth_val="${_ell_auth_val//\"/\\\"}";          # " -> \"
    printf 'header = "%s"\n' "${_ell_auth_val}" > "${auth_cfg}";
    opts+=(--config "${auth_cfg}");
  fi

  curl "${url}" "${opts[@]}" "${@}";
  status="${?}";
  # Remove the temp credential file after capturing curl's status. Cleanup is
  # explicit (rather than a RETURN trap) because there are no early returns
  # between creating auth_cfg and here, and doing it inline keeps the captured
  # exit status unambiguous regardless of shell trap semantics.
  if [ -n "${auth_cfg}" ]; then
    rm -f "${auth_cfg}";
  fi
  return "${status}";
}

# ell_curl_strerror <exit-code>: print a human-readable, actionable explanation
# for a curl exit code. Falls back to a generic message for codes not listed.
# See `man curl` (EXIT CODES) for the full list; only the ones users actually
# hit are spelled out here.
ell_curl_strerror() {
  case "${1}" in
    6)  printf 'could not resolve host (check ELL_API_URL and your network/DNS)' ;;
    7)  printf 'failed to connect (server down or wrong host/port in ELL_API_URL?)' ;;
    22) printf 'server returned an HTTP error (>= 400); check ELL_API_KEY, the model, and ELL_API_URL' ;;
    28) printf 'request timed out (raise ELL_MAX_TIME / ELL_CONNECT_TIMEOUT, or check the network)' ;;
    35) printf 'TLS handshake failed (check the endpoint supports HTTPS)' ;;
    52) printf 'empty reply from server' ;;
    56) printf 'network error while receiving data' ;;
    60) printf 'TLS certificate problem (untrusted or invalid certificate)' ;;
    3)  printf 'malformed URL (is ELL_API_URL set correctly?)' ;;
    *)  printf 'curl error' ;;
  esac
}

export -f _ell_curl_fail_opt;
export -f _ell_on_windows;
export -f _ell_fixup_file_url;
export -f _ell_url_is_secure;
export -f ell_curl;
export -f ell_curl_strerror;
