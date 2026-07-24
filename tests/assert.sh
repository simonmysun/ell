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
# shell options. These helpers only use POSIX-compatible constructs plus local.

_ASSERT_PASS=0;
_ASSERT_FAIL=0;

# _assert_show: render a value with control characters made visible.
_assert_show() {
  printf '%s' "${1}" | cat -v;
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

# assert_contains <name> <haystack> <needle>
# Succeeds if <haystack> contains the literal substring <needle>.
assert_contains() {
  local name="${1}" haystack="${2}" needle="${3}";
  case "${haystack}" in
    *"${needle}"*)
      _assert_pass "${name}";
      ;;
    *)
      _assert_fail "${name}";
      echo "  needle  : $(_assert_show "${needle}")";
      echo "  haystack: $(_assert_show "${haystack}")";
      ;;
  esac
}

# assert_not_contains <name> <haystack> <needle>
# Succeeds if <haystack> does NOT contain the literal substring <needle>.
# Useful for security assertions: "the secret must not survive".
assert_not_contains() {
  local name="${1}" haystack="${2}" needle="${3}";
  case "${haystack}" in
    *"${needle}"*)
      _assert_fail "${name}";
      echo "  unexpected needle: $(_assert_show "${needle}")";
      echo "  in haystack      : $(_assert_show "${haystack}")";
      ;;
    *)
      _assert_pass "${name}";
      ;;
  esac
}

# assert_success <name> <command...>
# Runs the command; passes if it exits 0. Command output is suppressed.
assert_success() {
  local name="${1}";
  shift;
  if "${@}" >/dev/null 2>&1; then
    _assert_pass "${name}";
  else
    _assert_fail "${name}";
    echo "  command failed (exit ${?}): ${*}";
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

# assert_summary
# Prints the pass/fail tally and returns non-zero if any assertion failed.
# Call this as the final line of a test script and rely on its exit status.
assert_summary() {
  echo "";
  echo "${_ASSERT_PASS} passed, ${_ASSERT_FAIL} failed";
  [ "${_ASSERT_FAIL}" -eq 0 ];
}
