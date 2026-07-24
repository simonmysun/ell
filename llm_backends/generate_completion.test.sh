#!/usr/bin/env bash

# Self-checking tests for llm_backends/generate_completion.sh (the dispatcher).
#
# The dispatcher sources a backend selected by ELL_API_STYLE. That value comes
# from the CLI/config/environment and used to be interpolated straight into a
# source path, so "../../tmp/evil" could source an arbitrary file as shell
# code. These tests lock in the validation: only a simple backend name that
# resolves to an existing backend file is accepted; slashes, "."/".." traversal
# and unknown names are rejected, and a traversal attempt never sources the
# targeted file.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";

ELL_LOG_LEVEL=0;
export ELL_LOG_LEVEL;
. "${DIR}/../helpers/logging.sh";

# The dispatcher resolves backends relative to BASE_DIR.
BASE_DIR="$(cd "${DIR}/.." && pwd)";
export BASE_DIR;

DISPATCH="${DIR}/generate_completion.sh";

# dispatch <style>: source the dispatcher with the given ELL_API_STYLE in an
# isolated subshell, discarding output. Returns the dispatcher's exit status.
# Sourcing a valid backend only defines functions; it performs no network I/O.
dispatch() (
  ELL_API_STYLE="${1}";
  export ELL_API_STYLE;
  # shellcheck source=/dev/null
  . "${DISPATCH}";
)

echo "generate_completion dispatcher tests";
echo "====================================";

# Valid, shipped backends are accepted.
assert_success "ell_echo backend loads" dispatch "ell_echo";
assert_success "openai backend loads" dispatch "openai";
assert_success "gemini backend loads" dispatch "gemini";

# Traversal / slash-bearing / empty names are rejected.
assert_failure "rejects parent traversal" dispatch "../../tmp";
assert_failure "rejects nested traversal" dispatch "../openai";
assert_failure "rejects embedded slash" dispatch "foo/bar";
assert_failure "rejects empty style" dispatch "";
assert_failure "rejects '.'" dispatch ".";
assert_failure "rejects '..'" dispatch "..";

# A syntactically valid but unknown backend name is rejected.
assert_failure "rejects unknown backend" dispatch "does_not_exist";

# A traversal attempt pointing at a real attacker-controlled file must NOT
# source it. Plant a marker-writing "backend" directory and reference it via a
# "../" traversal from the backends directory; the dispatcher must refuse.
EVIL_DIR="$(mktemp -d)";
trap 'rm -rf "${EVIL_DIR}"' EXIT;
mkdir -p "${EVIL_DIR}/evil";
MARKER="${EVIL_DIR}/sourced";
printf 'printf "x" > "%s"\n' "${MARKER}" > "${EVIL_DIR}/evil/generate_completion.sh";
# From "${BASE_DIR}/llm_backends", "../<abs-ish traversal>" would reach it if
# traversal were allowed. Any slash-bearing value is rejected before use.
dispatch "../${EVIL_DIR#/}/evil" >/dev/null 2>&1;
assert_success "traversal did not source the evil file" test ! -e "${MARKER}";

assert_summary;
