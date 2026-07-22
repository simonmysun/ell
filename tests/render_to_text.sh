#!/usr/bin/env bash

# Self-checking tests for helpers/render_to_text.awk, which strips ANSI /
# terminal escape sequences from `script`-recorded terminal output (used to
# build the shell context in record mode).
#
# Each case feeds a byte-exact input into the renderer and asserts the output
# matches an expected byte-exact result. The script exits non-zero if any case
# fails, so it can gate CI.
#
# The renderer is invoked exactly as ell.sh invokes it: under LC_ALL=C so the
# C1 control bytes (0x80-0x9f) are handled byte-for-byte.

RENDER="$(dirname "${0}")/../helpers/render_to_text.awk";

render() {
  LC_ALL=C awk -f "${RENDER}";
}

fail=0;
pass=0;

# assert_render <name> <input-file> <expected-file>
assert_render() {
  local name="${1}" in="${2}" exp="${3}" got;
  got="$(mktemp)";
  render < "${in}" > "${got}";
  if cmp -s "${got}" "${exp}"; then
    echo "PASS: ${name}";
    pass=$((pass + 1));
  else
    echo "FAIL: ${name}";
    echo "  input   : $(cat -v "${in}")";
    echo "  expected: $(cat -v "${exp}")";
    echo "  got     : $(cat -v "${got}")";
    fail=$((fail + 1));
  fi
  rm -f "${got}";
}

# case <name> <input-printf-format> <expected-printf-format>
# Builds the input and expected byte streams with printf (so control bytes are
# exact) and runs the assertion.
case_test() {
  local name="${1}" in_fmt="${2}" exp_fmt="${3}" in exp;
  in="$(mktemp)"; exp="$(mktemp)";
  printf "${in_fmt}" > "${in}";
  printf "${exp_fmt}" > "${exp}";
  assert_render "${name}" "${in}" "${exp}";
  rm -f "${in}" "${exp}";
}

echo "render_to_text tests";
echo "====================";

# 1. Plain text is passed through unchanged (no trailing newline added).
case_test "plain text, no trailing newline" \
  'hello world' \
  'hello world';

# 2. Plain text with a trailing newline keeps exactly one.
case_test "plain text with trailing newline" \
  'hello\n' \
  'hello\n';

# 3. CSI SGR colour codes are stripped, surrounding text preserved.
case_test "CSI colour codes" \
  '\033[31mRED\033[0m and \033[1;32mGREEN\033[0m\n' \
  'RED and GREEN\n';

# 4. Carriage returns are removed (typical of \r\n line endings from script).
case_test "carriage return removed" \
  'line1\r\nline2\r\n' \
  'line1\nline2\n';

# 5. OSC sequence (window title, BEL-terminated) is stripped.
case_test "OSC window title (BEL)" \
  '\033]0;my title\007visible\n' \
  'visible\n';

# 6. OSC sequence terminated by ST (ESC backslash) is stripped.
case_test "OSC (ST-terminated)" \
  'a\033]2;title\033\\b\n' \
  'ab\n';

# 7. Single backspace erases the preceding character.
case_test "single backspace erase" \
  'abc\bd\n' \
  'abd\n';

# 8. Multiple consecutive backspaces erase multiple characters.
#    "deep" \b -> "dee", "p" -> "deep", \b\b\b -> "d", "XYZ" -> "dXYZ".
case_test "multiple backspace erase" \
  'deep\bp\b\b\bXYZ\n' \
  'dXYZ\n';

# 9. Charset selection sequence (ESC ( B) is stripped.
case_test "charset selection ESC ( B" \
  'A\033(BB\n' \
  'AB\n';

# 10. A lone two-byte ESC sequence is stripped.
case_test "two-byte ESC sequence" \
  'x\033Xy\n' \
  'xy\n';

# 11. Single-byte C1 CSI introducer (0x9b) behaves like ESC [.
case_test "C1 CSI (0x9b)" \
  'p\x9b31mq\n' \
  'pq\n';

# 12. A realistic script(1) typescript: header/footer lines are plain text and
#     pass through; the recorded command output has its colours stripped and
#     its \r removed.
case_test "realistic typescript body" \
  'Script started on 2026-01-01\n\033[32mok\033[0m done\r\nsecond line\r\nScript done on 2026-01-01\n' \
  'Script started on 2026-01-01\nok done\nsecond line\nScript done on 2026-01-01\n';

# 13. Cursor movement / erase-line CSI sequences (as emitted by progress
#     output) are stripped, leaving the final visible text.
case_test "cursor/erase CSI sequences" \
  'loading\033[2K\033[1Gdone\n' \
  'loadingdone\n';

echo "";
echo "${pass} passed, ${fail} failed";

[ "${fail}" -eq 0 ];
