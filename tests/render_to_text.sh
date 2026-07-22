#!/usr/bin/env bash

# Self-checking tests for helpers/render_to_text.awk.
#
# render_to_text.awk is a line-level terminal emulator: it maintains a per-line
# cell buffer and cursor column, so cursor-movement and erase sequences take
# real effect. This matters for privacy in record mode -- text that was typed
# and then deleted (backspace, Ctrl-U, cursor editing) must not survive into
# the context sent to the LLM.
#
# Each case feeds a byte-exact input and asserts a byte-exact expected output.
# The script exits non-zero if any case fails.

RENDER="$(dirname "${0}")/../helpers/render_to_text.awk";

render() {
  LC_ALL=C awk -f "${RENDER}";
}

fail=0;
pass=0;

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

# --- Basic pass-through and escape stripping --------------------------------

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

# 4. A carriage return with nothing overwriting it after it leaves the line
#    text intact (cursor returns to column 0, then LF flushes the line).
case_test "CR before LF, no overwrite" \
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

# 7. Charset selection sequence (ESC ( B) is stripped.
case_test "charset selection ESC ( B" \
  'A\033(BB\n' \
  'AB\n';

# 8. A lone two-byte ESC sequence is stripped.
case_test "two-byte ESC sequence" \
  'x\033Xy\n' \
  'xy\n';

# 9. Single-byte C1 CSI introducer (0x9b) behaves like ESC [.
case_test "C1 CSI (0x9b)" \
  'p\x9b31mq\n' \
  'pq\n';

# --- Cursor movement and overwrite ------------------------------------------

# 10. Single backspace moves the cursor back; the next byte overwrites.
case_test "single backspace overwrite" \
  'abc\bd\n' \
  'abd\n';

# 11. Multiple backspaces then overwrite:
#     "deep" \b -> col3, "p" -> "deep", \b\b\b -> col1, "XYZ" -> "dXYZ".
case_test "multiple backspace overwrite" \
  'deep\bp\b\b\bXYZ\n' \
  'dXYZ\n';

# 12. Cursor-left (CSI D) then overwrite: "KEY=123" \033[3D "456" -> "KEY=456".
case_test "cursor-left overwrite (CSI D)" \
  'KEY=123\033[3D456\n' \
  'KEY=456\n';

# 13. Cursor-right (CSI C) leaves never-written columns as spaces.
case_test "cursor-right leaves spaces (CSI C)" \
  'ab\033[3Ccd\n' \
  'ab   cd\n';

# --- Erase sequences: deleted content must NOT survive -----------------------

# 14. Ctrl-U style redraw: type a secret, then \r + erase-to-end-of-line and
#     redraw the prompt. The secret must be gone.
case_test "Ctrl-U redraw erases secret (CR + CSI K)" \
  'prompt$ KEY=123\r\033[Kprompt$ ls\n' \
  'prompt$ ls\n';

# 15. Erase entire line (CSI 2K) wipes what was written before it.
case_test "erase whole line (CSI 2K)" \
  'secret\033[2K\rvisible\n' \
  'visible\n';

# 16. Erase from start of line to cursor (CSI 1K) blanks the head; because the
#     erased head columns become spaces up to the cursor, they render as
#     spaces before the surviving tail.
case_test "erase to cursor (CSI 1K)" \
  'abcdef\033[1Kxy\n' \
  '      xy\n';

# 17. Backspace-space-backspace (how readline erases one char) removes it.
case_test "readline single-char delete (BS SP BS)" \
  'ls foo\b \b\n' \
  'ls fo\n';

# --- Realistic recorded typescript ------------------------------------------

# 18. A realistic script(1) body: header/footer plain, coloured output has its
#     colours stripped and \r handled.
case_test "realistic typescript body" \
  'Script started on 2026-01-01\n\033[32mok\033[0m done\r\nsecond line\r\nScript done on 2026-01-01\n' \
  'Script started on 2026-01-01\nok done\nsecond line\nScript done on 2026-01-01\n';

# 19. Progress-style redraw (erase line + go to column 1) keeps only the final
#     visible text.
case_test "progress redraw (CSI 2K + CSI G)" \
  'loading\033[2K\033[1Gdone\n' \
  'done\n';

echo "";
echo "${pass} passed, ${fail} failed";

[ "${fail}" -eq 0 ];
