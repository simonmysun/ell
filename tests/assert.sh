#!/usr/bin/env bash

# Tiny, zero-dependency assertion library for ell's test suite.
#
# ell is pure Bash with no package manager, so instead of pulling in bats or
# shunit2 this file provides a handful of assert_* helpers built on the same
# byte-exact comparison approach already proven in render_to_text.sh.
#
# Usage:
#   . "$(dirname "${0}")/assert.sh";
#   assert_equals "name" "expected" "actual";
#   ...
#   assert_summary;   # prints "N passed, M failed" and returns non-zero on any failure
#
# Every assertion prints a single PASS/FAIL line. On failure the expected and
# actual values are shown with `cat -v` so invisible bytes (escape sequences,
# CR/LF, control chars) are visible. Call assert_summary as the last line of a
# test so the script exits non-zero when anything failed.

# set -o posix is intentionally NOT forced here: sourcing files decide their own
# shell options. These helpers target Bash (see shebang): mostly POSIX-style
# constructs plus a few Bash features (local, ${var//pat/repl}) used where they
# avoid correctness traps such as glob metacharacters in case patterns.

_ASSERT_PASS=0;
_ASSERT_FAIL=0;

# ell_timeout <seconds> <command...>
# Run <command...> under `timeout`, scaling the wall-clock budget by
# ELL_TEST_TIMEOUT_SCALE (default 1). Tests use short fixed budgets purely to
# catch hangs (infinite loops / EOF regressions), not to measure speed, so on a
# slow or heavily-loaded runner a genuinely-working path could otherwise exceed
# the budget and fail with 124. Set e.g. ELL_TEST_TIMEOUT_SCALE=3 there to widen
# every budget at once. If `timeout` is unavailable, the command is run directly
# (no hang protection, but the suite still works).
ell_timeout() {
  local secs="${1}";
  shift;
  local scale="${ELL_TEST_TIMEOUT_SCALE:-1}";
  # Integer-multiply the budget by the scale (both are plain integers).
  case "${scale}${secs}" in
    *[!0-9]*) scale=1 ;;  # non-integer scale/secs: fall back to no scaling
  esac
  local budget=$(( secs * scale ));
  if command -v timeout >/dev/null 2>&1; then
    timeout "${budget}" "${@}";
  else
    "${@}";
  fi
}

# _assert_show: render a value with control characters made visible.
_assert_show() {
  printf '%s' "${1}" | cat -v;
}

# assert_files_equal <name> <file-a> <file-b>: byte-exact comparison of two
# files without depending on cmp(1)/diff (diffutils), which is absent in some
# environments (e.g. a minimal MSYS2). Appending a sentinel 'x' before the
# command substitution preserves any trailing newlines that "$(...)" would
# strip, keeping the comparison byte-exact.
assert_files_equal() {
  local name="${1}" a b;
  a="$(cat "${2}"; printf x)";
  b="$(cat "${3}"; printf x)";
  if [ "${a}" = "${b}" ]; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  expected: $(_assert_show "$(cat "${2}")")";
    echo "  actual  : $(_assert_show "$(cat "${3}")")";
  fi
}

# _assert_pass / _assert_fail: record a result and print one status line.
_assert_pass() {
  _ASSERT_PASS=$((_ASSERT_PASS + 1));
  echo "PASS: ${1}";
}

_assert_fail() {
  _ASSERT_FAIL=$((_ASSERT_FAIL + 1));
  echo "FAIL: ${1}";
}

# assert_equals <name> <expected> <actual>
# Byte-exact string equality.
assert_equals() {
  local name="${1}" expected="${2}" actual="${3}";
  if [ "${actual}" = "${expected}" ]; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  expected: $(_assert_show "${expected}")";
    echo "  actual  : $(_assert_show "${actual}")";
  fi
}

# assert_not_equals <name> <unexpected> <actual>
assert_not_equals() {
  local name="${1}" unexpected="${2}" actual="${3}";
  if [ "${actual}" != "${unexpected}" ]; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  did not expect: $(_assert_show "${unexpected}")";
  fi
}

# _assert_haystack_has <haystack> <needle>
# Returns 0 if <haystack> contains <needle> as a *literal* substring, else 1.
#
# NOTE: `case "${haystack}" in *"${needle}"*)` cannot be used here. In a case
# pattern, glob metacharacters inside ${needle} (notably '[' ... ']', but also
# '?' and unquoted '*') keep their pattern meaning, so needles like
# '[EMAIL REDACTED]' are matched as character classes rather than literal text,
# producing false passes/failures. Bash parameter-expansion replacement with a
# double-quoted needle treats the needle literally, so we detect containment by
# checking whether removing the needle changes the string.
_assert_haystack_has() {
  local haystack="${1}" needle="${2}";
  # An empty needle is a substring of everything.
  [ -z "${needle}" ] && return 0;
  [ "${haystack//"${needle}"/}" != "${haystack}" ];
}

# assert_contains <name> <haystack> <needle>
# Succeeds if <haystack> contains the literal substring <needle>.
assert_contains() {
  local name="${1}" haystack="${2}" needle="${3}";
  if _assert_haystack_has "${haystack}" "${needle}"; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  needle  : $(_assert_show "${needle}")";
    echo "  haystack: $(_assert_show "${haystack}")";
  fi
}

# assert_not_contains <name> <haystack> <needle>
# Succeeds if <haystack> does NOT contain the literal substring <needle>.
# Useful for security assertions: "the secret must not survive".
assert_not_contains() {
  local name="${1}" haystack="${2}" needle="${3}";
  if _assert_haystack_has "${haystack}" "${needle}"; then
    _assert_fail "${name}";
    echo "  unexpected needle: $(_assert_show "${needle}")";
    echo "  in haystack      : $(_assert_show "${haystack}")";
  else
    _assert_pass "${name}";
  fi
}

# assert_success <name> <command...>
# Runs the command; passes if it exits 0. Command output is suppressed.
assert_success() {
  local name="${1}";
  shift;
  local status;
  # Capture the command's exit status immediately: any command run before this
  # (e.g. _assert_fail) would overwrite $?.
  "${@}" >/dev/null 2>&1;
  status="${?}";
  if [ "${status}" -eq 0 ]; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  command failed (exit ${status}): ${*}";
  fi
}

# assert_failure <name> <command...>
# Runs the command; passes if it exits non-zero. Command output is suppressed.
assert_failure() {
  local name="${1}";
  shift;
  if "${@}" >/dev/null 2>&1; then
    _assert_fail "${name}";
    echo "  command unexpectedly succeeded: ${*}";
  else
    _assert_pass "${name}";
  fi
}

# assert_matches <name> <string> <regex>
# Succeeds if <string> matches the extended regular expression <regex>. Uses
# bash's [[ =~ ]], so no external grep is spawned; the regex is unanchored
# (add ^...$ yourself for a full-string match).
assert_matches() {
  local name="${1}" string="${2}" regex="${3}";
  # The regex must be unquoted for [[ =~ ]] to treat it as a pattern.
  if [[ "${string}" =~ ${regex} ]]; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  regex : $(_assert_show "${regex}")";
    echo "  string: $(_assert_show "${string}")";
  fi
}

# assert_exits <name> <expected-status> -- <command...>
# Runs <command...> and passes if it exits with <expected-status>. Both stdout
# and stderr are discarded. This captures the status safely (a hazard when
# hand-written, since any command before reading $? overwrites it) and removes
# the repeated `cmd >/dev/null 2>&1; status="${?}"` boilerplate. The literal
# `--` separates the expected status from the command for readability.
assert_exits() {
  local name="${1}" expected="${2}";
  shift 2;
  if [ "x${1}" = "x--" ]; then
    shift;
  fi
  local status;
  "${@}" >/dev/null 2>&1;
  status="${?}";
  if [ "${status}" -eq "${expected}" ]; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  expected exit: ${expected}";
    echo "  actual exit  : ${status} (${*})";
  fi
}

# assert_summary
# Prints the pass/fail tally and returns non-zero if any assertion failed.
# Call this as the final line of a test script and rely on its exit status.
assert_summary() {
  echo "";
  echo "${_ASSERT_PASS} passed, ${_ASSERT_FAIL} failed";
  [ "${_ASSERT_FAIL}" -eq 0 ];
}
