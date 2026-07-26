#!/usr/bin/env bash

# Self-checking tests for llm_backends/http.sh (ell_curl).
#
# ell_curl centralises curl invocation so every backend gets timeouts and HTTP
# error handling. Rather than depend on a live server (the CI images are minimal
# and may lack python/nc), we stub `curl` with a shell function that records the
# arguments it was given, and assert that ell_curl passes the robustness options
# through. One real call against an unreachable address checks that a connect
# timeout actually bounds the wait.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";

ELL_LOG_LEVEL=0;
export ELL_LOG_LEVEL;
. "${DIR}/logging.sh";
. "${DIR}/http.sh";

echo "http / ell_curl tests";
echo "=====================";

# Stub curl: print every argument on its own line so we can inspect them.
ARGS_FILE="$(mktemp)";
trap 'rm -f "${ARGS_FILE}"' EXIT;
curl() {
  printf '%s\n' "${@}" > "${ARGS_FILE}";
  return 0;
}

# has_arg <value>: true if the stubbed curl received <value> as an argument.
has_arg() {
  grep -qxF -- "${1}" "${ARGS_FILE}";
}

# --- Option injection -------------------------------------------------------

# Resolve the fail option BEFORE the main call. _ell_curl_fail_opt probes with
# `curl --help`, which the stub also records; resolving it first (and letting it
# cache) keeps that probe from overwriting ARGS_FILE during the assertions.
# With curl stubbed, `--help` yields no match so the value is --fail here.
fail_opt="$(_ell_curl_fail_opt)";

ELL_CONNECT_TIMEOUT=7 ELL_MAX_TIME=0 \
  ell_curl "https://example.com" --header "X: 1" --data-binary @- </dev/null;

assert_success "url passed through"          has_arg "https://example.com";
assert_success "silent enabled"              has_arg "--silent";
assert_success "connect-timeout flag set"    has_arg "--connect-timeout";
assert_success "connect-timeout value used"  has_arg "7";
assert_success "max-time flag set"           has_arg "--max-time";
assert_success "caller header preserved"     has_arg "X: 1";
assert_success "caller data-binary preserved" has_arg "--data-binary";

# The fail option (either --fail-with-body on newer curl or --fail on older,
# here --fail because the stub's --help matches neither) is injected.
assert_success "fail option present" has_arg "${fail_opt}";
case "${fail_opt}" in
  --fail|--fail-with-body) _assert_pass "fail option is a known value";;
  *) _assert_fail "fail option is a known value"; echo "  got: ${fail_opt}";;
esac

# Default connect timeout is applied when the variable is unset.
unset ELL_CONNECT_TIMEOUT;
ell_curl "https://example.com" </dev/null;
assert_success "default connect-timeout (10) applied" has_arg "10";

# Extra options are appended when requested.
ELL_CURL_EXTRA_OPTS="--proto =https" ell_curl "https://example.com" </dev/null;
assert_success "extra opt --proto passed"  has_arg "--proto";
assert_success "extra opt value passed"    has_arg "=https";
unset ELL_CURL_EXTRA_OPTS;

# --- Auth header is not exposed on the command line -------------------------
# ELL_CURL_AUTH_HEADER must be passed via a --config file, never as an argv
# element, so the secret is not visible in ps / /proc/<pid>/cmdline. Use a stub
# that records argv and captures the --config file's contents.
CFG_FILE="$(mktemp)";
PERM_FILE="$(mktemp)";
trap 'rm -f "${ARGS_FILE}" "${CFG_FILE}" "${PERM_FILE}"' EXIT;
curl() {
  printf '%s\n' "${@}" > "${ARGS_FILE}";
  local prev="";
  for a in "${@}"; do
    if [ "${prev}" = "--config" ]; then
      cp "${a}" "${CFG_FILE}" 2>/dev/null;
      # Capture the permission bits while the file still exists (ell_curl removes
      # it after this call). GNU stat then BSD/macOS stat.
      { stat -c '%a' "${a}" 2>/dev/null || stat -f '%Lp' "${a}" 2>/dev/null; } > "${PERM_FILE}";
    fi
    prev="${a}";
  done
  return 0;
}

secret="Authorization: Bearer sk-DO-NOT-LEAK-123";
ELL_CURL_AUTH_HEADER="${secret}" ell_curl "https://example.com" --data-binary @- </dev/null;

# The secret must NOT appear anywhere in the argv the stub received.
if grep -qF -- "sk-DO-NOT-LEAK-123" "${ARGS_FILE}"; then
  _assert_fail "auth header value is not on the command line";
else
  _assert_pass "auth header value is not on the command line";
fi
# --config must be present, and the config file must carry the header.
assert_success "auth header passed via --config" has_arg "--config";
if grep -qF -- "sk-DO-NOT-LEAK-123" "${CFG_FILE}"; then
  _assert_pass "auth header delivered through the config file";
else
  _assert_fail "auth header delivered through the config file";
fi
# The temp config file must be mode 0600 (only the owner can read the secret).
# The last two octal digits (group, other) must be 0; strip any leading digit.
cfg_perms="$(cat "${PERM_FILE}" 2>/dev/null)";
case "${cfg_perms}" in
  600|0600) _assert_pass "temp auth config is mode 0600" ;;
  *) _assert_fail "temp auth config is mode 0600"; echo "  perms: ${cfg_perms}" ;;
esac
# The temp config file curl was pointed at must be removed after the call.
cfg_path="$(awk '/^--config$/{getline; print; exit}' "${ARGS_FILE}")";
if [ -n "${cfg_path}" ] && [ -e "${cfg_path}" ]; then
  _assert_fail "temp auth config is cleaned up";
  echo "  still present: ${cfg_path}";
else
  _assert_pass "temp auth config is cleaned up";
fi
unset ELL_CURL_AUTH_HEADER;

# --- Refuse credentials over a plaintext remote URL -------------------------
# _ell_url_is_secure classifies where it is safe to send a credential.
assert_success "https is secure"           _ell_url_is_secure "https://api.openai.com/v1";
assert_success "file is secure"            _ell_url_is_secure "file:///tmp/x.json";
assert_success "http loopback is secure"   _ell_url_is_secure "http://localhost:8080/v1";
assert_success "http 127.0.0.1 is secure"  _ell_url_is_secure "http://127.0.0.1/v1";
assert_failure "http remote is insecure"   _ell_url_is_secure "http://api.example.com/v1";

# With an auth header and a plaintext remote URL, ell_curl must refuse and NOT
# invoke curl (so the key is never sent in cleartext).
insecure_ran=0;
curl() { insecure_ran=1; return 0; }
ELL_CURL_AUTH_HEADER="Authorization: Bearer sk-INSECURE" \
  ell_curl "http://api.example.com/v1" --data-binary @- </dev/null >/dev/null 2>&1;
insecure_status="${?}";
assert_not_equals "refuses credential over remote http" "0" "${insecure_status}";
assert_equals     "curl not invoked when refused" "0" "${insecure_ran}";

# The explicit opt-out allows it.
optout_ran=0;
curl() { optout_ran=1; return 0; }
ELL_ALLOW_INSECURE_URL=true ELL_CURL_AUTH_HEADER="Authorization: Bearer sk-INSECURE" \
  ell_curl "http://api.example.com/v1" --data-binary @- </dev/null >/dev/null 2>&1;
assert_equals "opt-out allows insecure send" "1" "${optout_ran}";
unset ELL_ALLOW_INSECURE_URL ELL_CURL_AUTH_HEADER;

# Without a credential, a plaintext remote URL is allowed (nothing to leak).
noauth_ran=0;
curl() { noauth_ran=1; return 0; }
ell_curl "http://api.example.com/v1" --data-binary @- </dev/null >/dev/null 2>&1;
assert_equals "no-auth plaintext URL is allowed" "1" "${noauth_ran}";

# Restore the recording stub for any later assertions.
curl() {
  printf '%s\n' "${@}" > "${ARGS_FILE}";
  return 0;
}

# --- Real timeout against an unreachable address ----------------------------
# Drop the stub so the real curl runs.
unset -f curl;
if command -v curl >/dev/null 2>&1; then
  # 10.255.255.1 is a TEST-NET / non-routable address; the connect must time out
  # quickly rather than hang. Assert curl exits non-zero within the bound.
  ELL_CONNECT_TIMEOUT=2 ELL_MAX_TIME=3 \
    ell_curl "http://10.255.255.1:9/" --data-binary @- </dev/null >/dev/null 2>&1;
  status="${?}";
  if [ "${status}" -ne 0 ]; then
    _assert_pass "unreachable host fails (does not hang)";
  else
    _assert_fail "unreachable host fails (does not hang)";
  fi
else
  echo "SKIP: real timeout check (curl not installed)";
fi

# --- ell_curl_strerror translates curl exit codes ---------------------------
# Common curl exit codes must map to a readable, actionable message rather than
# a bare number; unknown codes fall back to a generic message.
assert_contains "code 6 mentions host resolution"  "$(ell_curl_strerror 6)"  "resolve host";
assert_contains "code 7 mentions connect failure"  "$(ell_curl_strerror 7)"  "connect";
assert_contains "code 28 mentions timeout"         "$(ell_curl_strerror 28)" "timed out";
assert_contains "code 60 mentions certificate"     "$(ell_curl_strerror 60)" "certificate";
assert_equals   "unknown code falls back"          "curl error" "$(ell_curl_strerror 250)";

assert_summary;
