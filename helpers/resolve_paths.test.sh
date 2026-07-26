#!/usr/bin/env bash

# Self-checking tests for helpers/resolve_paths.sh.
#
# list_plugin_hooks:
#   * enabled hooks are discovered,
#   * hooks carrying a ".disabled" suffix are skipped (this is how the bundled
#     redaction plugin ships disabled by default),
#   * duplicate <plugin-dir>/<hook-file> across roots is de-duplicated with the
#     highest-priority root winning,
#   * results are ordered by "<plugin-dir>/<hook-file>",
#   * paths with spaces are handled (glob iteration, not `ls` parsing),
#   * nullglob is restored afterwards.
#
# resolve_template:
#   * a valid name resolves across the search roots,
#   * a name containing "/" or "."/".." is rejected (no path traversal),
#   * ELL_TEMPLATE_PATH works with or without a trailing slash.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";

ELL_LOG_LEVEL=0;
export ELL_LOG_LEVEL;
. "${DIR}/logging.sh";
. "${DIR}/resolve_paths.sh";

echo "resolve_paths / list_plugin_hooks tests";
echo "=======================================";

# Build isolated search roots so the developer's real ~/.config etc. are not
# consulted. _ell_search_roots derives roots from these four variables.
WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

export HOME="${WORK}/home";
export XDG_CONFIG_HOME="${WORK}/xcfg";
export XDG_DATA_HOME="${WORK}/xdata";
BASE_DIR="${WORK}/base";
export BASE_DIR;
mkdir -p "${HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${BASE_DIR}";

mkplugin() {
  # mkplugin <root> <plugin> <file>
  mkdir -p "${1}/plugins/${2}";
  printf '#!/usr/bin/env bash\ncat\n' > "${1}/plugins/${2}/${3}";
  chmod +x "${1}/plugins/${2}/${3}";
}

# An enabled hook in the bundled (BASE_DIR) root.
mkplugin "${BASE_DIR}" "alpha" "10_post_input.sh";
# A disabled hook (redaction-style): must be skipped.
mkplugin "${BASE_DIR}" "redaction" "50_post_input.sh.disabled";
# Another enabled hook, higher numeric prefix -> should sort after alpha.
mkplugin "${BASE_DIR}" "zeta" "90_post_input.sh";

hooks="$(list_plugin_hooks _post_input.sh)";

assert_contains     "enabled alpha hook discovered" "${hooks}" "/plugins/alpha/10_post_input.sh";
assert_contains     "enabled zeta hook discovered"  "${hooks}" "/plugins/zeta/90_post_input.sh";
assert_not_contains "disabled hook skipped"         "${hooks}" "redaction/50_post_input.sh.disabled";
assert_not_contains "disabled hook not matched at all" "${hooks}" "redaction";

# Ordering: alpha (10_) must come before zeta (90_).
first_line="$(printf '%s\n' "${hooks}" | head -n 1)";
assert_contains "alpha sorts before zeta" "${first_line}" "alpha/10_post_input.sh";

# De-duplication + priority: the same plugin-dir/hook-file in a higher-priority
# root (XDG_CONFIG_HOME) must override the bundled copy, and only one should be
# listed.
mkplugin "${BASE_DIR}"          "shared" "20_post_input.sh";
mkplugin "${XDG_CONFIG_HOME}/ell" "shared" "20_post_input.sh";
hooks="$(list_plugin_hooks _post_input.sh)";
count="$(printf '%s\n' "${hooks}" | grep -c "shared/20_post_input.sh" || true)";
assert_equals   "shared hook de-duplicated to one entry" "1" "${count}";
assert_contains "shared hook resolved from XDG config (higher priority)" \
  "${hooks}" "${XDG_CONFIG_HOME}/ell/plugins/shared/20_post_input.sh";
assert_not_contains "bundled shared copy not used" \
  "${hooks}" "${BASE_DIR}/plugins/shared/20_post_input.sh";

# A disabled hook that is the ONLY copy of its plugin yields no entry for it.
mkplugin "${BASE_DIR}" "onlydisabled" "30_post_input.sh.disabled";
hooks="$(list_plugin_hooks _post_input.sh)";
assert_not_contains "sole disabled plugin absent" "${hooks}" "onlydisabled";

# A filename that both matches the hook suffix AND contains ".disabled" (either
# in a directory component or the file name itself) must still be skipped by the
# awk filter, not just by the glob. Directory-component case:
mkplugin "${BASE_DIR}" "beta.disabled" "40_post_input.sh";
# File-name case (matches "*_post_input.sh" yet is marked disabled):
mkdir -p "${BASE_DIR}/plugins/gamma";
printf '#!/usr/bin/env bash\ncat\n' > "${BASE_DIR}/plugins/gamma/50.disabled_post_input.sh";
chmod +x "${BASE_DIR}/plugins/gamma/50.disabled_post_input.sh";
hooks="$(list_plugin_hooks _post_input.sh)";
assert_not_contains "disabled directory component skipped" "${hooks}" "beta.disabled";
assert_not_contains "disabled filename skipped by awk filter" "${hooks}" "50.disabled_post_input.sh";

# A plugin directory containing a space is handled: glob iteration keeps it in
# one piece, whereas parsing `ls` output would have split it.
mkplugin "${BASE_DIR}" "with space" "60_post_input.sh";
hooks="$(list_plugin_hooks _post_input.sh)";
assert_contains "plugin path with space discovered" "${hooks}" "with space/60_post_input.sh";

# nullglob is restored to its prior (off) state after the call.
shopt -u nullglob;
list_plugin_hooks _post_input.sh >/dev/null;
if shopt -q nullglob; then
  _assert_fail "nullglob restored after list_plugin_hooks";
else
  _assert_pass "nullglob restored after list_plugin_hooks";
fi

# --- resolve_template -------------------------------------------------------

# A template in the bundled templates/ dir resolves.
mkdir -p "${BASE_DIR}/templates";
printf '{}\n' > "${BASE_DIR}/templates/mytemplate.json";
resolved="$(resolve_template "mytemplate" 2>/dev/null)";
assert_equals "valid template resolves" "${BASE_DIR}/templates/mytemplate.json" "${resolved}";

# A name that traverses out of the template dir is rejected.
assert_failure "template traversal rejected"  resolve_template "../../etc/passwd";
assert_failure "template with slash rejected" resolve_template "sub/dir";
assert_failure "empty template name rejected" resolve_template "";
assert_failure "dotdot template name rejected" resolve_template "..";

# ELL_TEMPLATE_PATH resolves with and without a trailing slash.
mkdir -p "${WORK}/tpl";
printf '{}\n' > "${WORK}/tpl/explicit.json";
got_noslash="$(ELL_TEMPLATE_PATH="${WORK}/tpl" resolve_template "explicit" 2>/dev/null)";
assert_equals "ELL_TEMPLATE_PATH without trailing slash" "${WORK}/tpl/explicit.json" "${got_noslash}";
got_slash="$(ELL_TEMPLATE_PATH="${WORK}/tpl/" resolve_template "explicit" 2>/dev/null)";
assert_equals "ELL_TEMPLATE_PATH with trailing slash" "${WORK}/tpl/explicit.json" "${got_slash}";

assert_summary;
