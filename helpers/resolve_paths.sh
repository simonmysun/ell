#!/usr/bin/env bash

# Path resolution helpers implementing the XDG Base Directory Specification
# while remaining backward compatible with the legacy ~/.ellrc.d layout.
#
# Templates and plugins are searched across several roots, in priority order:
#   1. ${XDG_CONFIG_HOME:-$HOME/.config}/ell   (user overrides)
#   2. ${XDG_DATA_HOME:-$HOME/.local/share}/ell
#   3. $HOME/.ellrc.d                          (legacy install location)
#   4. ${BASE_DIR}                             (files shipped with ell)
#
# BASE_DIR is expected to be set by the caller (ell.sh) to the directory the
# ell script lives in, so the bundled templates and plugins are always found.

# _ell_search_roots: print the ordered list of root directories to search,
# one per line. BASE_DIR is printed last so bundled resources act as the
# built-in fallback.
_ell_search_roots() {
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/ell";
  printf '%s\n' "${XDG_DATA_HOME:-${HOME}/.local/share}/ell";
  printf '%s\n' "${HOME}/.ellrc.d";
  if [ -n "${BASE_DIR}" ]; then
    printf '%s\n' "${BASE_DIR}";
  fi
}

# resolve_template <name>: print the full path to the first matching
# "<name>.json" template found in the search roots. If ELL_TEMPLATE_PATH is
# set explicitly (e.g. via -T / --template-path) it is treated as a single
# directory and takes precedence, preserving the previous behaviour.
# Returns non-zero if no template file is found.
resolve_template() {
  local name="${1}" root candidate;
  if [ -n "${ELL_TEMPLATE_PATH}" ]; then
    candidate="${ELL_TEMPLATE_PATH}${name}.json";
    if [ -f "${candidate}" ]; then
      printf '%s' "${candidate}";
      return 0;
    fi
    return 1;
  fi
  while IFS= read -r root; do
    candidate="${root}/templates/${name}.json";
    if [ -f "${candidate}" ]; then
      printf '%s' "${candidate}";
      return 0;
    fi
  done < <(_ell_search_roots)
  return 1;
}

# list_plugin_hooks <hook-suffix>: print, one per line, every plugin hook
# script matching "*/<hook-suffix>" across all search roots' plugins/
# directories.
#
# The search roots are visited in priority order, so if the same plugin
# (identified by "<plugin-dir>/<hook-file>") exists in more than one root,
# only the highest-priority copy is kept. This prevents a plugin bundled with
# ell from also running from a legacy ~/.ellrc.d clone.
#
# The surviving hooks are ordered by "<plugin-dir>/<hook-file>" so the numeric
# ordering prefix (e.g. 90_pre_output.sh) is respected regardless of which
# root a plugin lives in.
list_plugin_hooks() {
  local suffix="${1}" root;
  {
    while IFS= read -r root; do
      ls "${root}"/plugins/*/*"${suffix}" 2>/dev/null;
    done < <(_ell_search_roots)
  } | awk -F/ '
    {
      key = $(NF-1) "/" $NF;
      if (!(key in seen)) {
        seen[key] = 1;
        print key "\t" $0;
      }
    }
  ' | sort | cut -f2-;
}

export -f _ell_search_roots resolve_template list_plugin_hooks 2>/dev/null;
