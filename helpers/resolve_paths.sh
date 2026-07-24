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
#
# The name is validated as a single path segment (no "/", not "." or ".."), so
# it cannot traverse out of the template directories (e.g. -t ../../secret).
resolve_template() {
  local name="${1}" root candidate dir;

  case "${name}" in
    */*|""|.|..)
      logging_error "Invalid template name: '${name}' (must be a simple name without '/')";
      return 1;
      ;;
  esac

  if [ -n "${ELL_TEMPLATE_PATH}" ]; then
    # Normalise the directory so a trailing slash is optional: "-T dir" and
    # "-T dir/" both work (previously only a trailing slash resolved).
    dir="${ELL_TEMPLATE_PATH%/}";
    candidate="${dir}/${name}.json";
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
#
# A hook whose filename contains ".disabled" is skipped, so a plugin can be
# turned off by renaming its script (e.g. 50_post_input.sh -> the same name
# with a .disabled suffix). This is how the bundled redaction plugin ships:
# disabled by default until the user removes the .disabled suffix.
list_plugin_hooks() {
  local suffix="${1}" root hook;
  # Enable nullglob so a non-matching glob expands to nothing instead of the
  # literal pattern, and iterate the glob directly rather than parsing `ls`
  # output (which breaks on paths containing spaces or newlines).
  local nullglob_was_set=0;
  shopt -q nullglob && nullglob_was_set=1;
  shopt -s nullglob;
  {
    while IFS= read -r root; do
      for hook in "${root}"/plugins/*/*"${suffix}"; do
        printf '%s\n' "${hook}";
      done
    done < <(_ell_search_roots)
  } | awk -F/ '
    # Skip disabled hooks: any path component containing ".disabled".
    $0 ~ /\.disabled(\/|$)/ { next; }
    $NF ~ /\.disabled/ { next; }
    {
      key = $(NF-1) "/" $NF;
      if (!(key in seen)) {
        seen[key] = 1;
        print key "\t" $0;
      }
    }
  ' | sort | cut -f2-;
  # Restore nullglob to its previous state so we do not change it globally.
  if [ "${nullglob_was_set}" -eq 0 ]; then
    shopt -u nullglob;
  fi
}

export -f _ell_search_roots resolve_template list_plugin_hooks 2>/dev/null;
