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

# The trust check relies on POSIX permission bits (group/other write). On some
# platforms -- notably Windows Git Bash / MSYS over NTFS -- chmod cannot create
# a genuinely group/world-writable file and `stat` does not report those bits
# reliably, so the "reject insecure file" path cannot be exercised there.
# Probe once: create a world-writable file and see whether the write bits stick.
# If they do not, the environment lacks trustworthy POSIX perms and the
# perms-dependent assertions are SKIPped (see docs/Configuration.md, "Windows").
posix_perms_trustworthy() {
  local probe="${WORK}/.perm_probe" p;
  printf '' > "${probe}";
  chmod 666 "${probe}" 2>/dev/null || { rm -f "${probe}"; return 1; }
  p="$(stat -c '%a' "${probe}" 2>/dev/null || stat -f '%Lp' "${probe}" 2>/dev/null)";
  rm -f "${probe}";
  # Expect both group (2) and other (2) write bits to be present.
  case "${p}" in
    *[2367][2367]) return 0 ;;
    *) return 1 ;;
  esac
}
if posix_perms_trustworthy; then
  PERMS_OK=true;
else
  PERMS_OK=false;
fi

# A file owned by us with private (0600) permissions is trusted.
printf 'x=1\n' > "${WORK}/private";
chmod 600 "${WORK}/private";
assert_success "0600 file is trusted" _config_is_trusted "${WORK}/private";

# 0644 (readable by all but writable only by owner) is still trusted.
printf 'x=1\n' > "${WORK}/readable";
chmod 644 "${WORK}/readable";
assert_success "0644 file is trusted" _config_is_trusted "${WORK}/readable";

# Group-writable and world-writable files are rejected. Only meaningful where
# POSIX permission bits are trustworthy (see the probe above).
if [ "${PERMS_OK}" = "true" ]; then
  printf 'x=1\n' > "${WORK}/group_w";
  chmod 660 "${WORK}/group_w";
  assert_failure "group-writable file is rejected" _config_is_trusted "${WORK}/group_w";

  printf 'x=1\n' > "${WORK}/world_w";
  chmod 606 "${WORK}/world_w";
  assert_failure "world-writable file is rejected" _config_is_trusted "${WORK}/world_w";
else
  echo "SKIP: group-writable file is rejected (POSIX perms not trustworthy here)";
  echo "SKIP: world-writable file is rejected (POSIX perms not trustworthy here)";
fi

# A trusted file is actually sourced by _load_config_file.
printf 'ELL_TEST_TRUSTED=loaded\n' > "${WORK}/trusted_cfg";
chmod 600 "${WORK}/trusted_cfg";
loaded="$(_load_config_file "${WORK}/trusted_cfg" "" >/dev/null 2>&1; printf '%s' "${ELL_TEST_TRUSTED}")";
assert_equals "trusted config is sourced" "loaded" "${loaded}";

# A world-writable file is NOT sourced, and refusing it is logged visibly.
# Same POSIX-perms caveat as above.
if [ "${PERMS_OK}" = "true" ]; then
  printf 'ELL_TEST_EVIL=pwned\n' > "${WORK}/evil_cfg";
  chmod 666 "${WORK}/evil_cfg";
  skipped="$(_load_config_file "${WORK}/evil_cfg" "" >/dev/null 2>&1; printf '%s' "${ELL_TEST_EVIL-unset}")";
  assert_equals "untrusted config is not sourced" "unset" "${skipped}";

  # Refusing an insecure config must be visible at the DEFAULT log level (2):
  # otherwise the user's config is silently ignored and looks broken. The
  # refusal is logged at error level, so it appears at level 2 (unlike a warn
  # at >=3).
  reject_msg="$(
    ELL_LOG_LEVEL=2 _config_is_trusted "${WORK}/evil_cfg" 2>&1 >/dev/null;
  )";
  assert_contains "insecure config refusal is visible at level 2" \
    "${reject_msg}" "Ignoring config";
  assert_contains "insecure config refusal suggests chmod" \
    "${reject_msg}" "chmod 600";
else
  echo "SKIP: untrusted config is not sourced (POSIX perms not trustworthy here)";
  echo "SKIP: insecure config refusal is visible at level 2 (POSIX perms not trustworthy here)";
  echo "SKIP: insecure config refusal suggests chmod (POSIX perms not trustworthy here)";
fi

# A missing file is a silent no-op (returns success, sources nothing).
assert_success "missing file is a no-op" _load_config_file "${WORK}/does_not_exist" "";

# --- load_config() end-to-end behaviour -------------------------------------
#
# load_config resolves files via HOME / XDG_CONFIG_HOME / PWD / ELL_CONFIG.
# Point HOME and XDG_CONFIG_HOME at an isolated tree so the developer's real
# config is never read, and run load_config in a subshell so its exports and
# option changes (allexport) do not leak between cases.

HOME_DIR="${WORK}/home";
XDG_DIR="${WORK}/xdg";
mkdir -p "${HOME_DIR}" "${XDG_DIR}/ell";

# XDG config sets a value; the legacy ~/.ellrc overrides it. Later files win.
printf 'ELL_LLM_MODEL=from-xdg\nELL_FROM_XDG=1\n' > "${XDG_DIR}/ell/config";
chmod 600 "${XDG_DIR}/ell/config";
printf 'ELL_LLM_MODEL=from-home\n' > "${HOME_DIR}/.ellrc";
chmod 600 "${HOME_DIR}/.ellrc";

result="$(
  cd "${WORK}" || exit 1;      # PWD has no .ellrc here
  HOME="${HOME_DIR}" XDG_CONFIG_HOME="${XDG_DIR}";
  export HOME XDG_CONFIG_HOME;
  unset ELL_LLM_MODEL ELL_FROM_XDG;
  load_config >/dev/null 2>&1;
  printf '%s|%s' "${ELL_LLM_MODEL}" "${ELL_FROM_XDG}";
)";
assert_equals "later config overrides earlier; values are set" "from-home|1" "${result}";

# Config assignments are exported (allexport), visible to child processes.
exported="$(
  cd "${WORK}" || exit 1;
  HOME="${HOME_DIR}" XDG_CONFIG_HOME="${XDG_DIR}";
  export HOME XDG_CONFIG_HOME;
  unset ELL_FROM_XDG;
  load_config >/dev/null 2>&1;
  bash -c 'printf "%s" "${ELL_FROM_XDG}"';
)";
assert_equals "config values are exported to children" "1" "${exported}";

# A variable already set in the environment must NOT be overridden by config,
# even though the config file assigns it. This is load_config's core contract.
preserved="$(
  cd "${WORK}" || exit 1;
  HOME="${HOME_DIR}" XDG_CONFIG_HOME="${XDG_DIR}";
  ELL_LLM_MODEL=from-env;
  export HOME XDG_CONFIG_HOME ELL_LLM_MODEL;
  load_config >/dev/null 2>&1;
  printf '%s' "${ELL_LLM_MODEL}";
)";
assert_equals "environment is not overridden by config" "from-env" "${preserved}";

# An explicit ELL_CONFIG that does not exist is fatal (non-zero exit).
# load_config calls `exit 1`, which terminates the command-substitution
# subshell, so run it in its own subshell and inspect that subshell's status.
(
  cd "${WORK}" || exit 1;
  HOME="${HOME_DIR}" XDG_CONFIG_HOME="${XDG_DIR}" ELL_CONFIG="${WORK}/nope.conf";
  export HOME XDG_CONFIG_HOME ELL_CONFIG;
  load_config >/dev/null 2>&1;
);
assert_not_equals "missing ELL_CONFIG is fatal" "0" "${?}";

# An explicit, trusted ELL_CONFIG is loaded and wins over the other files.
printf 'ELL_LLM_MODEL=from-explicit\n' > "${WORK}/explicit.conf";
chmod 600 "${WORK}/explicit.conf";
explicit="$(
  cd "${WORK}" || exit 1;
  HOME="${HOME_DIR}" XDG_CONFIG_HOME="${XDG_DIR}" ELL_CONFIG="${WORK}/explicit.conf";
  export HOME XDG_CONFIG_HOME ELL_CONFIG;
  unset ELL_LLM_MODEL;
  load_config >/dev/null 2>&1;
  printf '%s' "${ELL_LLM_MODEL}";
)";
assert_equals "explicit ELL_CONFIG is loaded last" "from-explicit" "${explicit}";

assert_summary;
