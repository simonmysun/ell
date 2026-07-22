#!/usr/bin/awk -f

# Strip ANSI/terminal escape sequences and control codes from recorded
# terminal output (produced by `script`), turning it back into plain text.
#
# This is an awk reimplementation of the former render_to_text.perl. Perl was
# originally used because GNU sed and POSIX bash lack PCRE features such as
# non-greedy matching and iterative backspace handling. awk cannot express
# non-greedy quantifiers either, so the OSC/DCS/PM/APC sequences are matched
# with "negated character class" patterns (e.g. [^BEL ESC]* up to the
# terminator), which is the standard portable way to emulate .*? .
#
# Run it under a single-byte locale (LC_ALL=C) so the high C1 control bytes
# (0x80-0x9f) are matched byte-for-byte rather than being interpreted as
# multibyte UTF-8 characters.
#
# Reference for the sequence list (CC BY-SA 4.0):
# https://unix.stackexchange.com/questions/14684/removing-control-chars-including-console-codes-colours-from-script-output

# Rewritten from original perl code:
# while (<>) {
#   s/ \e[ #%()*+\-.\/]. |
#     \r | # Remove extra carriage returns also
#     (?:\e\[|\x9b) [ -?]* [@-~] | # CSI ... Cmd
#     (?:\e\]|\x9d) .*? (?:\e\\|[\a\x9c]) | # OSC ... (ST|BEL)
#     (?:\e[P^_]|[\x90\x9e\x9f]) .*? (?:\e\\|\x9c) | # (DCS|PM|APC) ... ST
#     \e.|[\x80-\x9f] //xg;
#     1 while s/[^\b][\b]//g;
#   print;
# }


BEGIN {
  # Slurp the entire input as one record so the exact byte content, including
  # its internal newlines and whether or not it ends with one, is preserved.
  # "^$" is the portable awk idiom for reading the whole stream at once.
  RS = "^$";

  ESC = sprintf("%c", 27);   # \e  ESC
  BEL = sprintf("%c", 7);    # \a  BEL
  BS  = sprintf("%c", 8);    # \b  backspace
  # C1 control bytes used as single-byte sequence introducers / terminators.
  C9B = sprintf("%c", 155);  # 0x9b  CSI
  C9C = sprintf("%c", 156);  # 0x9c  ST  (string terminator)
  C9D = sprintf("%c", 157);  # 0x9d  OSC

  # Character set selection: ESC followed by an intermediate byte from the
  # set " #%()*+-./" and one final byte. "-" is placed last so it is a
  # literal inside the bracket expression.
  CHARSET = ESC "[ #%()*+./-].";

  # CSI: (ESC [ | 0x9b) parameter/intermediate bytes then a final byte @-~.
  CSI = "(" ESC "\\[|" C9B ")[ -?]*[@-~]";

  # OSC: (ESC ] | 0x9d) ... (ESC \ | BEL | 0x9c)
  # Emulate the non-greedy body with a negated class that stops at any byte
  # that could begin/complete the terminator. Newline is excluded too so the
  # match cannot span lines, matching perl's line-by-line, non-/s behaviour.
  OSC = "(" ESC "\\]|" C9D ")[^\n" BEL ESC C9C "]*(" ESC "\\\\|[" BEL C9C "])";

  # DCS/PM/APC: (ESC P | ESC ^ | ESC _ | 0x90 | 0x9e | 0x9f) ... (ESC \ | 0x9c)
  C90 = sprintf("%c", 144);
  C9E = sprintf("%c", 158);
  C9F = sprintf("%c", 159);
  DCS = "(" ESC "[P^_]|[" C90 C9E C9F "])[^\n" ESC C9C "]*(" ESC "\\\\|" C9C ")";

  # Any other two-byte ESC sequence, or a lone C1 control byte 0x80-0x9f.
  OTHER = ESC "." "|[" sprintf("%c", 128) "-" sprintf("%c", 159) "]";

  # A carriage return is dropped as well.
  CR = "\r";
}

# The whole input arrives as a single record ($0) thanks to RS="^$".
{
  buf = $0;

  # Order matches the original: charset, CR, CSI, OSC, DCS/PM/APC, other.
  gsub(CHARSET, "", buf);
  gsub(CR, "", buf);
  gsub(CSI, "", buf);
  gsub(OSC, "", buf);
  gsub(DCS, "", buf);
  gsub(OTHER, "", buf);

  # Backspace handling: repeatedly delete a "visible char + backspace" pair so
  # that overstrike / erase behaviour collapses to the final visible text.
  # Equivalent to perl's: 1 while s/[^\b][\b]//g;
  while (gsub("[^" BS "]" BS, "", buf)) {
    # keep collapsing until no more pairs remain
  }

  # Do not append a trailing newline: $0 already contains the original one if
  # it was present, and the caller feeds this straight into JSON assembly.
  printf "%s", buf;
}
