#!/usr/bin/env bash

# Meta-tests for the assertion library itself (tests/assert.sh), covering the
# newer helpers assert_matches and assert_exits. The library is the foundation
# of every other test, so a regression in it could silently make assertions
# pass when they should fail. We exercise each helper in an isolated subshell
# and check whether it reports PASS or FAIL, rather than trusting it on itself.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

META_OUT="$(mktemp)";
trap 'rm -f "${META_OUT}"' EXIT;

# run_assert <helper-and-args...>: run one assertion helper in a clean subshell
# (fresh counters) and print the single PASS/FAIL word it emitted.
run_assert() {
  (
    _ASSERT_PASS=0; _ASSERT_FAIL=0;
    "${@}" >"${META_OUT}" 2>&1;
    # The helper printed "PASS: ..." or "FAIL: ..." as its first line.
    head -n1 "${META_OUT}" | cut -d: -f1;
  );
}

echo "assert library meta-tests";
echo "=========================";

# --- assert_matches ---------------------------------------------------------
assert_equals "matches: anchored timestamp regex" "PASS" \
  "$(run_assert assert_matches n '[2026-01-02 03:04:05]' '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]')";
assert_equals "matches: simple pattern present" "PASS" \
  "$(run_assert assert_matches n 'error: boom' 'err(or)?:')";
assert_equals "matches: non-matching fails" "FAIL" \
  "$(run_assert assert_matches n 'hello' '^world$')";
# A regex metacharacter behaves as a pattern (not a literal), unlike the
# literal substring helpers.
assert_equals "matches: dot is a metachar" "PASS" \
  "$(run_assert assert_matches n 'axc' 'a.c')";

# --- assert_exits -----------------------------------------------------------
assert_equals "exits: true is 0" "PASS" \
  "$(run_assert assert_exits n 0 -- true)";
assert_equals "exits: false is 1" "PASS" \
  "$(run_assert assert_exits n 1 -- false)";
assert_equals "exits: wrong code fails" "FAIL" \
  "$(run_assert assert_exits n 0 -- false)";
# The `--` separator is optional.
assert_equals "exits: works without --" "PASS" \
  "$(run_assert assert_exits n 0 true)";
# A specific non-zero status is matched exactly.
assert_equals "exits: exact non-zero status" "PASS" \
  "$(run_assert assert_exits n 3 -- sh -c 'exit 3')";

# --- ell_timeout ------------------------------------------------------------
# Only run these where `timeout` exists (ell_timeout runs the command directly
# otherwise, which would make the "budget too small" case hang).
#
# A timed-out command exits non-zero, but the exact code differs: GNU coreutils
# `timeout` returns 124, while busybox `timeout` (alpine) kills with SIGTERM and
# returns 143. So "timed out" is asserted as "non-zero", and completion within
# budget as the command's own status.
if command -v timeout >/dev/null 2>&1; then
  # Budget too small: a 2s sleep under a 1s budget times out (non-zero).
  ELL_TEST_TIMEOUT_SCALE=1 ell_timeout 1 sleep 2 >/dev/null 2>&1;
  assert_not_equals "ell_timeout enforces the budget" "0" "${?}";

  # Scaling widens the budget: the same sleep under 1s*3 completes (0).
  ELL_TEST_TIMEOUT_SCALE=3 ell_timeout 1 sleep 2 >/dev/null 2>&1;
  assert_equals "ELL_TEST_TIMEOUT_SCALE widens the budget" "0" "${?}";

  # A non-integer scale falls back to no scaling (budget stays 1s -> times out).
  ELL_TEST_TIMEOUT_SCALE=abc ell_timeout 1 sleep 2 >/dev/null 2>&1;
  assert_not_equals "invalid scale falls back to 1" "0" "${?}";

  # A command that finishes within budget returns its own status.
  ell_timeout 5 sh -c 'exit 7' >/dev/null 2>&1;
  assert_equals "ell_timeout preserves the command's status" "7" "${?}";
else
  echo "SKIP: ell_timeout budget tests (timeout not available)";
fi

assert_summary;
