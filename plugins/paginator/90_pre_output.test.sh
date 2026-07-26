#!/usr/bin/env bash

# Self-checking tests for plugins/paginator/90_pre_output.sh.
#
# The paginator is a pre_output hook. When stdout is a terminal (TO_TTY=true) it
# paginates using the cursor position and /dev/tty, which needs a real pty and
# is not unit-testable here. But its other, critical guarantee IS testable: when
# stdout is not a terminal (TO_TTY=false) -- e.g. piped to a file or another
# program -- it must pass the model output through completely untouched, never
# swallowing, reordering or rewriting bytes.
#
# These tests pin that passthrough behaviour byte-for-byte.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../../tests/assert.sh";

PAGINATOR="${DIR}/90_pre_output.sh";

# page <text>: run <text> through the paginator with TO_TTY=false and print the
# result.
page() {
  printf '%s' "${1}" | TO_TTY=false bash "${PAGINATOR}";
}

echo "paginator passthrough tests";
echo "===========================";

# Plain text is passed through unchanged.
assert_equals "plain text unchanged" "hello world" "$(page 'hello world')";

# Multi-line content is preserved.
multi="$(printf 'line1\nline2\nline3')";
assert_equals "multi-line preserved" "${multi}" "$(page "${multi}")";

# ANSI escape sequences in the content are passed through, not consumed.
ansi="$(printf '\033[1mbold\033[0m text')";
assert_equals "ANSI content preserved" "${ansi}" "$(page "${ansi}")";

# Leading/trailing whitespace and tabs survive.
spaced="$(printf '  a\tb  ')";
assert_equals "whitespace/tabs preserved" "${spaced}" "$(page "${spaced}")";

# Byte-exact check over mixed content including blank lines, so any difference
# (including a lost/added newline) is caught. assert_files_equal does the
# byte-exact comparison without depending on cmp (see tests/assert.sh).
WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;
printf 'a\tb\n\n  spaced  \nunicode: 世界 😀\n' > "${WORK}/in";
TO_TTY=false bash "${PAGINATOR}" < "${WORK}/in" > "${WORK}/out";
assert_files_equal "passthrough is byte-identical" "${WORK}/in" "${WORK}/out";

# Empty input yields empty output (no hang, no extra bytes).
assert_equals "empty input yields empty output" "" "$(printf '' | TO_TTY=false bash "${PAGINATOR}")";

assert_summary;
