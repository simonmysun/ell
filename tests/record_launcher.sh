#!/usr/bin/env bash

# End-to-end test for record mode locating ell correctly.
#
# Record mode re-execs ell inside `script -c "<cmd>"`. That command used to be a
# bare `ell`, which only works when ell is installed on PATH; running in place
# (./ell.sh) or from an uninstalled checkout failed with "ell: command not
# found". The fix re-execs "${BASE_DIR}/ell" as an absolute, shell-quoted path.
#
# This test drives record+interactive mode from a checkout that is NOT on PATH
# and whose directory contains a space (to also exercise the quoting), and
# asserts the inner ell actually ran (its echoed payload appears) and that no
# "command not found" occurred. It does not assert a clean exit: record mode
# wraps `script`, whose handling of a piped (non-TTY) stdin is a separate issue,
# so the whole thing is bounded by `timeout`.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

REPO_DIR="$(cd "${DIR}/.." && pwd)";

if ! command -v script >/dev/null 2>&1; then
  echo "SKIP: record_launcher (script(1) not available)";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi

echo "record launcher tests";
echo "=====================";

# Copy the checkout into a path containing a space so the launcher path must be
# quoted, and run it without adding it to PATH.
WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;
SPACED="${WORK}/dir with space";
mkdir -p "${SPACED}";
cp -r "${REPO_DIR}/." "${SPACED}/repo" 2>/dev/null;

out_file="${WORK}/rec.out";
err_file="${WORK}/rec.err";

# Build a PATH that has the tools record mode needs but definitely NOT `ell`, so
# the test proves record works without ell on PATH. Rather than guess which
# system directories hold the tools (and risk also exposing an installed ell,
# e.g. both bash and ell in /usr/local/bin), symlink exactly the tools we need
# into a dedicated bin dir and use only that. Any tool that cannot be resolved
# means we cannot isolate; skip cleanly.
SAFE_BIN="${WORK}/safebin";
mkdir -p "${SAFE_BIN}";
_missing_tool="";
for t in bash script env mktemp dirname chmod cat rm cp tail head grep awk sed printf date stty tr cut; do
  tp="$(command -v "${t}" 2>/dev/null)";
  if [ -n "${tp}" ]; then
    # Best-effort: symlink the tool into the isolated bin. `ln -s` can fail on
    # platforms without real symlinks (e.g. MSYS2), so fall back to a copy and
    # silence the error; the runnability probe below is the real gate.
    ln -sf "${tp}" "${SAFE_BIN}/${t}" 2>/dev/null \
      || cp -f "${tp}" "${SAFE_BIN}/${t}" 2>/dev/null || :;
  fi
done
SAFE_PATH="${SAFE_BIN}";
# bash and script are mandatory for record mode; if either is missing we already
# skipped above (script) or cannot proceed.
if [ ! -e "${SAFE_BIN}/bash" ]; then
  echo "SKIP: record_launcher (bash not resolvable for isolated PATH)";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi
# The isolated PATH must actually be able to run bash. On some platforms a
# copied/symlinked bash cannot start (e.g. MSYS2, where bash.exe needs
# msys-2.0.dll resolved relative to its original location: "cannot open shared
# object file"). In that case this isolation technique is not viable, so SKIP
# rather than report a false failure.
if ! PATH="${SAFE_PATH}" bash -c 'exit 0' >/dev/null 2>&1; then
  echo "SKIP: record_launcher (isolated bash not runnable in this environment)";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi
if PATH="${SAFE_PATH}" command -v ell >/dev/null 2>&1; then
  echo "SKIP: an 'ell' is reachable even on a minimal PATH; cannot isolate";
  assert_summary;
  return 0 2>/dev/null || exit 0;
fi

# Feed one prompt then EOF; bound with timeout so the known script+pipe EOF
# behaviour cannot hang the suite. Run with the ell-free PATH.
(
  cd "${SPACED}/repo" || exit 1;
  printf 'RECORD_LAUNCH_XYZ\n' | ell_timeout 12 \
    env PATH="${SAFE_PATH}" ELL_TEMPLATE_PATH="${SPACED}/repo/templates/" \
    ./ell.sh --api-style ell_echo -m gpt-4o --api-disable-streaming -r -i \
    >"${out_file}" 2>"${err_file}";
);

combined="$(cat "${out_file}" "${err_file}" 2>/dev/null)";

# The inner ell must have been located and run: its echoed request payload
# contains the prompt. If record had exec'd a bare `ell` not on PATH, we would
# instead see a "command not found" and no payload.
assert_contains "record mode located and ran the inner ell" "${combined}" "RECORD_LAUNCH_XYZ";
# The launcher itself must resolve. Check specifically that the ell launcher
# path was not reported as not-found, rather than matching a bare "not found"
# (which could also come from an unrelated optional tool like stty on a minimal
# PATH and is not what this test is about).
assert_not_contains "record mode resolved the ell launcher" "${combined}" "ell: No such file";
assert_not_contains "record mode did not hit ell command-not-found" "${combined}" "ell: command not found";

assert_summary;
