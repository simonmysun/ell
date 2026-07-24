#!/usr/bin/env bash

# Self-checking tests for helpers/load_config.sh.
#
# Config files are *sourced*, i.e. executed as shell code, so a config file
# that another user could plant or tamper with is an arbitrary-code-execution
# vector (notably $PWD/.ellrc when ell is run inside an untrusted directory).
#
# load_config now refuses to source any config file that is not owned by the
# current user (or root) and that is writable by group or others. These tests
# lock in that trust check: insecure files must be skipped, secure files must
# still load, and a missing file must be a no-op.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";

ELL_LOG_LEVEL=0;
export ELL_LOG_LEVEL;
. "${DIR}/logging.sh";
. "${DIR}/load_config.sh";

echo "load_config tests";
echo "=================";

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

# A file owned by us with private (0600) permissions is trusted.
printf 'x=1\n' > "${WORK}/private";
chmod 600 "${WORK}/private";
assert_success "0600 file is trusted" _config_is_trusted "${WORK}/private";

# 0644 (readable by all but writable only by owner) is still trusted.
printf 'x=1\n' > "${WORK}/readable";
chmod 644 "${WORK}/readable";
assert_success "0644 file is trusted" _config_is_trusted "${WORK}/readable";

# Group-writable files are rejected.
printf 'x=1\n' > "${WORK}/group_w";
chmod 660 "${WORK}/group_w";
assert_failure "group-writable file is rejected" _config_is_trusted "${WORK}/group_w";

# World-writable files are rejected.
printf 'x=1\n' > "${WORK}/world_w";
chmod 606 "${WORK}/world_w";
assert_failure "world-writable file is rejected" _config_is_trusted "${WORK}/world_w";

# A trusted file is actually sourced by _load_config_file.
printf 'ELL_TEST_TRUSTED=loaded\n' > "${WORK}/trusted_cfg";
chmod 600 "${WORK}/trusted_cfg";
loaded="$(_load_config_file "${WORK}/trusted_cfg" "" >/dev/null 2>&1; printf '%s' "${ELL_TEST_TRUSTED}")";
assert_equals "trusted config is sourced" "loaded" "${loaded}";

# A world-writable file is NOT sourced: its assignment must not take effect.
printf 'ELL_TEST_EVIL=pwned\n' > "${WORK}/evil_cfg";
chmod 666 "${WORK}/evil_cfg";
skipped="$(_load_config_file "${WORK}/evil_cfg" "" >/dev/null 2>&1; printf '%s' "${ELL_TEST_EVIL-unset}")";
assert_equals "untrusted config is not sourced" "unset" "${skipped}";

# A missing file is a silent no-op (returns success, sources nothing).
assert_success "missing file is a no-op" _load_config_file "${WORK}/does_not_exist" "";

assert_summary;
