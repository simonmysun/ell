#!/usr/bin/awk -f

# Render recorded terminal output (produced by `script`) back into the plain
# text a human would have seen, then feed it as context to the LLM.
#
# This is a small *line-level terminal emulator*. Unlike a plain "strip the
# escape codes" filter, it maintains a per-line cell buffer and a cursor
# column, so cursor movement and erase sequences actually take effect. That
# matters for privacy: content typed and then deleted with Ctrl-U, cursor
# editing, or "\r + erase-line" redraws is genuinely removed instead of being
# left behind for the model to read.
#
# Handled per line:
#   printable byte  -> write at cursor, advance cursor
#   \b (BS)         -> move cursor left (no erase; later output overwrites)
#   \r (CR)         -> cursor to column 0
#   \n (LF)         -> flush the current line and start a new one
#   ESC [ ... K     -> erase in line: 0/none = cursor..end, 1 = start..cursor,
#                      2 = whole line
#   ESC [ ... G     -> cursor to absolute column (1-based param)
#   ESC [ ... C     -> cursor right by n (default 1)
#   ESC [ ... D     -> cursor left by n (default 1)
#   other ESC [ ... -> consumed, no visible effect (colours, etc.)
#   OSC / DCS / PM / APC / charset / lone ESC / C1 bytes -> consumed
#
# Run under LC_ALL=C so bytes are handled one at a time (no multibyte
# interpretation), matching how the recorded stream is structured.

function flush_line(   c, out) {
  # Emit cells 0 .. maxcol-1, filling never-written interior columns with
  # spaces (as a real terminal would show them). Trailing unwritten columns
  # are not emitted.
  out = "";
  for (c = 0; c < maxcol; c++) {
    if (c in cell)
      out = out cell[c];
    else
      out = out " ";
  }
  # Trim trailing spaces. On a real terminal a deleted character (e.g. the
  # "\b \b" readline uses) leaves a blank cell at the end of the line; that is
  # invisible noise, so it is dropped rather than fed to the model. Interior
  # spaces are preserved.
  sub(/ +$/, "", out);
  outbuf = outbuf out;
  # Reset line state.
  delete cell;
  cur = 0;
  maxcol = 0;
}

function put(ch) {
  cell[cur] = ch;
  cur++;
  if (cur > maxcol)
    maxcol = cur;
}

# _ord: byte value (0-255) of a single-byte string, via a lookup table built
# in BEGIN. Used to detect UTF-8 lead / continuation bytes.
function _ord(c) {
  return ORD[c];
}

function erase(from, to,   c) {
  for (c = from; c <= to; c++)
    delete cell[c];
  # Shrink maxcol if we erased the tail.
  while (maxcol > 0 && !((maxcol - 1) in cell))
    maxcol--;
}

BEGIN {
  # Slurp the whole input as one record so byte content is preserved exactly.
  #
  # RS = "^$" is the portable "read the entire file as one record" idiom: it is
  # an anchor-only regex that can never match any actual text, so no record
  # separator is ever found and the whole stream becomes a single record. This
  # was verified to keep the input intact -- including blank lines and trailing
  # newlines -- on gawk, one-true-awk (nawk) and busybox awk (the CI runtime).
  #
  # A single literal byte as RS is deliberately NOT used: the input is a raw
  # `script` terminal recording that may contain arbitrary bytes (including NUL
  # and every control byte), so there is no byte guaranteed to be absent. Any
  # byte that did occur would silently split the record and corrupt the exact
  # byte-for-byte content this emulator depends on.
  RS = "^$";

  ESC = sprintf("%c", 27);
  CR  = sprintf("%c", 13);
  LF  = sprintf("%c", 10);
  BS  = sprintf("%c", 8);
  BEL = sprintf("%c", 7);

  # Byte-value lookup table for _ord().
  for (_b = 0; _b < 256; _b++)
    ORD[sprintf("%c", _b)] = _b;

  # NOTE: single-byte C1 controls (0x80-0x9f) are deliberately NOT treated as
  # control codes. In a UTF-8 terminal those byte values are common as
  # continuation bytes of multibyte characters (e.g. many CJK characters), and
  # real recordings always introduce escape sequences with ESC (0x1b), never
  # with a lone C1 byte. Treating C1 bytes as controls corrupted UTF-8 text
  # (Chinese input/output) and could even swallow the rest of the context.
}

{
  s = $0;
  n = length(s);
  outbuf = "";
  delete cell;
  cur = 0;
  maxcol = 0;

  i = 1;
  while (i <= n) {
    ch = substr(s, i, 1);

    # --- CSI: ESC [ ... final ------------------------------------------------
    if (ch == ESC && i < n && substr(s, i + 1, 1) == "[") {
      i += 2;
      params = "";
      # Collect parameter / intermediate bytes (0x20-0x3f) until a final byte.
      while (i <= n) {
        cc = substr(s, i, 1);
        if (cc ~ /[0-9;?:> ]/) { params = params cc; i++; continue; }
        break;
      }
      if (i > n) break;
      final = substr(s, i, 1);
      i++;
      # Numeric first parameter (default handled per command).
      np = params; gsub(/[;?:> ].*$/, "", np);
      if (final == "K") {
        p = (np == "" ? 0 : np + 0);
        if (p == 0)      erase(cur, maxcol - 1);
        else if (p == 1) erase(0, cur);
        else if (p == 2) erase(0, maxcol - 1);
      } else if (final == "G") {
        p = (np == "" ? 1 : np + 0);
        cur = p - 1; if (cur < 0) cur = 0;
      } else if (final == "C") {
        p = (np == "" ? 1 : np + 0);
        cur += p;
      } else if (final == "D") {
        p = (np == "" ? 1 : np + 0);
        cur -= p; if (cur < 0) cur = 0;
      }
      # Any other CSI (SGR colours 'm', cursor up/down, etc.) has no effect on
      # the single-line text model and is simply consumed.
      continue;
    }

    # --- OSC: ESC ] ... (BEL | ST) -------------------------------------------
    if (ch == ESC && i < n && substr(s, i + 1, 1) == "]") {
      i += 2;
      while (i <= n) {
        cc = substr(s, i, 1);
        if (cc == BEL) { i++; break; }
        if (cc == ESC && i < n && substr(s, i + 1, 1) == "\\") { i += 2; break; }
        i++;
      }
      continue;
    }

    # --- DCS / PM / APC: ESC P|^|_ ... ST ------------------------------------
    if (ch == ESC && i < n && substr(s, i + 1, 1) ~ /[P^_]/) {
      i += 2;
      while (i <= n) {
        cc = substr(s, i, 1);
        if (cc == ESC && i < n && substr(s, i + 1, 1) == "\\") { i += 2; break; }
        i++;
      }
      continue;
    }

    # --- Charset selection: ESC ( ) * + etc. + one final byte ----------------
    if (ch == ESC && i < n && substr(s, i + 1, 1) ~ /[ #%()*+.\/-]/) {
      i += 3;  # ESC, intermediate, final
      continue;
    }

    # --- Any other ESC x (two-byte) ------------------------------------------
    if (ch == ESC) {
      i += 2;
      continue;
    }

    # --- Control / cursor bytes ----------------------------------------------
    if (ch == LF) { flush_line(); outbuf = outbuf LF; i++; continue; }
    if (ch == CR) { cur = 0; i++; continue; }
    if (ch == BS) { cur--; if (cur < 0) cur = 0; i++; continue; }

    # --- Printable character -------------------------------------------------
    # Group UTF-8 multibyte sequences into a single cell so a wide character is
    # kept intact and occupies one logical column. A leading byte 0xC0-0xF7 is
    # followed by 1-3 continuation bytes (0x80-0xBF).
    b = _ord(ch);
    if (b >= 192 && b <= 247) {
      if      (b >= 240) { need = 3; }   # 4-byte
      else if (b >= 224) { need = 2; }   # 3-byte
      else               { need = 1; }   # 2-byte
      ch2 = ch;
      k = 1;
      while (k <= need && (i + k) <= n) {
        nb = _ord(substr(s, i + k, 1));
        if (nb < 128 || nb > 191) break;   # not a continuation byte
        ch2 = ch2 substr(s, i + k, 1);
        k++;
      }
      put(ch2);
      i += length(ch2);
      continue;
    }

    put(ch);
    i++;
  }

  # Flush any trailing partial line (input without a final newline).
  if (maxcol > 0 || cur > 0)
    flush_line();

  printf "%s", outbuf;
}
