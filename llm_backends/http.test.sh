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
. "${DIR}/../helpers/logging.sh";
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

assert_summary;
