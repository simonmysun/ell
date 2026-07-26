#!/usr/bin/env bash

# Tests for ell.sh's terminal-size handling (PAGE_SIZE / COLUMNS).
#
# ell reads the terminal size from `stty size`. When ell runs without a
# controlling terminal -- the common case when its output is piped to a file or
# another program -- `stty size` fails/returns nothing, and ell must fall back
# to sane defaults (PAGE_SIZE=24, COLUMNS=80) rather than leaving them empty
# (which would break the paginator's arithmetic). PAGE_SIZE and COLUMNS are
# exported, so a pre_output hook can observe the values ell computed.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

# A pre_output hook that appends the PAGE_SIZE / COLUMNS ell exported, so we can
# assert on the values from outside.
CFG="${WORK}/cfg";
mkdir -p "${CFG}/ell/plugins/probe" "${WORK}/data" "${WORK}/home";
{
  printf '#!/usr/bin/env bash\n';
  printf 'cat\n';
  printf 'printf "\\nELL_PAGE_SIZE=%%s ELL_COLUMNS=%%s\\n" "${PAGE_SIZE}" "${COLUMNS}"\n';
} > "${CFG}/ell/plugins/probe/10_pre_output.sh";
chmod +x "${CFG}/ell/plugins/probe/10_pre_output.sh";

echo "terminal size tests";
echo "===================";

# Run with no controlling terminal for stdout (piped), so `stty size` fails.
out="$(
  printf '' | env \
    XDG_CONFIG_HOME="${CFG}" XDG_DATA_HOME="${WORK}/data" HOME="${WORK}/home" \
    ELL_TEMPLATE_PATH="${DIR}/../templates/" TO_TTY=false \
    "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming "hi" \
    2>/dev/null;
)";

# Fallbacks must be applied (not empty) when stty size is unavailable.
assert_contains "PAGE_SIZE falls back to 24 without a tty" "${out}" "ELL_PAGE_SIZE=24";
assert_contains "COLUMNS falls back to 80 without a tty"    "${out}" "ELL_COLUMNS=80";
assert_not_contains "PAGE_SIZE is never empty"             "${out}" "ELL_PAGE_SIZE= ";

# The run itself must still succeed despite stty failing.
status="$(
  printf '' | env \
    XDG_CONFIG_HOME="${CFG}" XDG_DATA_HOME="${WORK}/data" HOME="${WORK}/home" \
    ELL_TEMPLATE_PATH="${DIR}/../templates/" TO_TTY=false \
    "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming "hi" \
    >/dev/null 2>&1; printf '%s' "${?}";
)";
assert_equals "ell succeeds without a tty (stty failure tolerated)" "0" "${status}";

assert_summary;
