#!/usr/bin/env bash

# End-to-end tests for stdout-to-file redirection (-o / --output-file).
#
# ell redirects stdout to ELL_OUTPUT_FILE only in plain (non-record,
# non-interactive) mode. The guard used to compare `"${ELL_RECORD}" != "xtrue"`
# with the 'x' prefix on only one side, so it was always true and the redirect
# fired even in record/interactive mode. These tests pin the correct behaviour:
#   * plain mode + -o FILE  -> completion goes to FILE, terminal stdout is empty
#   * plain mode, no -o     -> completion goes to stdout
#   * interactive mode + -o -> stdout is NOT hijacked by the -o redirect
#
# The ell_echo backend echoes the request body, so we can see where output went.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

COMMON_ENV=(ELL_TEMPLATE_PATH="${DIR}/../templates/" TO_TTY=false);

echo "output redirect tests";
echo "=====================";

# --- Plain mode + -o FILE: output goes to the file, not to stdout -----------
out_file="${WORK}/out.json";
stdout="$(printf '' | env "${COMMON_ENV[@]}" \
  "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming \
  -o "${out_file}" UNIQUE_REDIRECT_XYZ 2>/dev/null)";
assert_equals   "plain mode -o leaves stdout empty" "" "${stdout}";
file_contents="$(cat "${out_file}" 2>/dev/null)";
assert_contains "plain mode -o writes completion to the file" "${file_contents}" "UNIQUE_REDIRECT_XYZ";

# --- Plain mode, no -o: output goes to stdout -------------------------------
stdout="$(printf '' | env "${COMMON_ENV[@]}" \
  "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming \
  UNIQUE_STDOUT_XYZ 2>/dev/null)";
assert_contains "no -o writes completion to stdout" "${stdout}" "UNIQUE_STDOUT_XYZ";

# --- Interactive mode + -o: stdout is NOT hijacked by the -o redirect -------
# Point ELL_TMP_SHELL_LOG at an existing file so record-mode re-entry is skipped
# and ell goes straight into the interactive loop (the path the inner ell runs
# under `script`). With the bug, the -o file redirect fired even here; with the
# fix, the interactive completion is still emitted on stdout. Bounded by timeout
# so an EOF-loop regression cannot hang the suite.
shell_log="${WORK}/shelllog";
: > "${shell_log}";
redirect_file="${WORK}/should_stay_empty.json";
stdout="$(printf 'INTERACTIVE_XYZ\n' | timeout 10 env "${COMMON_ENV[@]}" \
  ELL_TMP_SHELL_LOG="${shell_log}" \
  "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming \
  -o "${redirect_file}" -i 2>/dev/null)";
assert_contains "interactive completion still reaches stdout" "${stdout}" "INTERACTIVE_XYZ";

assert_summary;
