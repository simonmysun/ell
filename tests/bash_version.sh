#!/usr/bin/env bash

# Tests for ell.sh's bash version gate (the check at the very top of ell.sh).
#
# ell requires bash >= 4.1. The guard is:
#   if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
#     if [ "${BASH_VERSINFO:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 1 ]; then
#       ...reject...
#   else ...reject... fi
#
# BASH_VERSINFO is read-only so we cannot fake an old bash in-process. Instead we
# (1) replicate the exact predicate and assert its accept/reject decision for a
# range of (major, minor) versions, (2) confirm the real ell running under the
# current (supported) bash is not rejected, and (3) confirm the error message
# and exit code match what ell.sh emits.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

# version_ok <major> <minor>: mirror of ell.sh's gate. Returns 0 (accept) if the
# version is supported (>= 4.1), non-zero (reject) otherwise.
version_ok() {
  local major="${1}" minor="${2}";
  if [ "${major}" -ge 4 ]; then
    if [ "${major}" -eq 4 ] && [ "${minor}" -lt 1 ]; then
      return 1;
    fi
  else
    return 1;
  fi
  return 0;
}

echo "bash version gate tests";
echo "=======================";

# Supported: 4.1 and up.
assert_success "4.1 accepted"  version_ok 4 1;
assert_success "4.2 accepted"  version_ok 4 2;
assert_success "5.0 accepted"  version_ok 5 0;
assert_success "5.2 accepted"  version_ok 5 2;
assert_success "6.0 accepted"  version_ok 6 0;

# Unsupported: below 4.1.
assert_failure "4.0 rejected"  version_ok 4 0;
assert_failure "3.2 rejected"  version_ok 3 2;
assert_failure "2.05 rejected" version_ok 2 5;
assert_failure "0 rejected"    version_ok 0 0;

# The real ell, under the current (supported) bash, must not be rejected by the
# version gate: `--version` should succeed and print the version line.
ver_out="$("${DIR}/../ell" --version 2>&1)";
ver_status="${?}";
assert_equals   "ell --version exits 0 on supported bash" "0" "${ver_status}";
assert_contains "ell --version prints the version"        "${ver_out}" "${ELL_VERSION:-0.1.1}";
assert_not_contains "supported bash is not rejected"      "${ver_out}" "is required to run";

# The rejection message (as written in ell.sh) names 4.1, matching README/CI.
gate_msg="$(grep -m1 'is required to run this script' "${DIR}/../ell.sh")";
assert_contains "version message says 4.1" "${gate_msg}" "4.1 or higher";
assert_not_contains "version message does not say 4.2" "${gate_msg}" "4.2";

assert_summary;
