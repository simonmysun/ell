#!/usr/bin/env bash

# End-to-end tests for the `ell` launcher's path resolution.
#
# `ell` is a thin wrapper that resolves its own directory (following symlinks)
# and execs the real `${ELL_DIR}/ell.sh`, so the bundled helpers/templates are
# always found no matter how ell was invoked. This is the documented install
# path (symlinking ell into ~/.local/bin), so the symlink resolution must work.
#
# These tests invoke the launcher directly, by absolute path, and through
# symlinks in other directories (both absolute and relative), and confirm each
# time that the real ell.sh ran (its ell_echo output carries a unique marker).

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

# The symlink cases require real symbolic links. On Windows Git Bash `ln -s`
# usually degrades to a copy (unless MSYS=winsymlinks:nativestrict and the user
# can create links), so those cases cannot be exercised there and are SKIPped
# (see docs/Configuration.md, "Windows"). Probe once: make a link and confirm
# the OS reports it as a symlink whose target reads back.
symlinks_supported() {
  local t="${WORK}/.link_probe" l="${WORK}/.link_probe_ln";
  printf '' > "${t}";
  rm -f "${l}";
  ln -s "${t}" "${l}" 2>/dev/null || { rm -f "${t}" "${l}"; return 1; }
  if [ -L "${l}" ]; then rm -f "${t}" "${l}"; return 0; fi
  rm -f "${t}" "${l}";
  return 1;
}
if symlinks_supported; then SYMLINKS_OK=true; else SYMLINKS_OK=false; fi

# run_launcher <path-to-launcher> <marker> [workdir]
# Invoke the launcher (optionally from <workdir>) against the ell_echo backend
# and print its output. The marker is the prompt, which ell_echo echoes back in
# the request body, proving the real ell.sh ran.
run_launcher() {
  local launcher="${1}" marker="${2}" workdir="${3:-${DIR}}";
  (
    cd "${workdir}" || exit 1;
    printf '' | ell_timeout 8 env TO_TTY=false ELL_TEMPLATE_PATH="${DIR}/../templates/" \
      "${launcher}" --api-style ell_echo -m gpt-4o --api-disable-streaming "${marker}" \
      2>/dev/null;
  );
}

echo "launcher tests";
echo "==============";

# Direct absolute path.
out="$(run_launcher "$(cd "${DIR}/.." && pwd)/ell" MARK_ABS)";
assert_contains "launcher runs via absolute path" "${out}" "MARK_ABS";

if [ "${SYMLINKS_OK}" = "true" ]; then
  # Symlink in another directory pointing at the launcher (absolute target).
  ln -s "$(cd "${DIR}/.." && pwd)/ell" "${WORK}/ell_abs_link";
  out="$(run_launcher "${WORK}/ell_abs_link" MARK_SYMLINK)";
  assert_contains "launcher runs via absolute symlink" "${out}" "MARK_SYMLINK";

  # Relative symlink invoked from its own directory (exercises the relative
  # link-target resolution in the launcher).
  (
    cd "${WORK}" || exit 1;
    ln -s "ell_abs_link" "ell_rel_link";
  );
  out="$(run_launcher "./ell_rel_link" MARK_REL "${WORK}")";
  assert_contains "launcher runs via relative symlink" "${out}" "MARK_REL";

  # A chain of symlinks resolves to the real ell.sh.
  ln -s "${WORK}/ell_rel_link" "${WORK}/ell_chain";
  out="$(run_launcher "${WORK}/ell_chain" MARK_CHAIN)";
  assert_contains "launcher runs via a symlink chain" "${out}" "MARK_CHAIN";
else
  echo "SKIP: launcher runs via absolute symlink (real symlinks unsupported here)";
  echo "SKIP: launcher runs via relative symlink (real symlinks unsupported here)";
  echo "SKIP: launcher runs via a symlink chain (real symlinks unsupported here)";
fi

assert_summary;
