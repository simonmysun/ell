#!/usr/bin/env bash

# Self-checking tests for plugins/syntax_highlight/50_post_llm.sh.
#
# This plugin is a streaming, best-effort Markdown highlighter. It only does
# anything when TO_TTY=true; otherwise it is a transparent `cat -`. It is by far
# the largest file in the repo and had no tests, so a regression in the state
# machine could silently corrupt or drop output.
#
# Rather than assert exact ANSI escape sequences, we override the STYLE_* hooks
# with easy-to-spot text markers (e.g. STYLE_HEADING="<H>") and assert:
#   * the visible text of the input is always preserved,
#   * each construct (heading, list, bold/italic, strikethrough, inline code,
#     code block, link) is wrapped in the corresponding style marker,
#   * plain text is not decorated with content markers,
#   * inside a fenced code block Markdown is NOT interpreted,
#   * with TO_TTY=false the input passes through byte-for-byte.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../../tests/assert.sh";

HL="${DIR}/50_post_llm.sh";

# hl <input>: run the highlighter with TO_TTY=true and marker styles, printing
# the highlighted output. Markers are plain text so output is easy to assert on.
hl() {
  printf '%s' "${1}" | \
  TO_TTY=true \
  STYLE_RESET='<R>' STYLE_HEADING='<H>' STYLE_LIST='<L>' STYLE_CODE='<C>' \
  STYLE_CODE_BLOCK='<CB>' STYLE_BLOCKQUOTE='<BQ>' STYLE_BOLD='<B>' STYLE_ITALIC='<I>' \
  STYLE_STRIKETHROUGH='<S>' STYLE_LINK_TEXT='<LT>' STYLE_URL='<U>' STYLE_TITLE='<T>' \
  STYLE_IMAGE_TEXT='<IMG>' STYLE_PUNCTUATION='<P>' \
    bash "${HL}";
}

echo "syntax_highlight tests";
echo "======================";

# --- Heading ----------------------------------------------------------------
out="$(hl "$(printf '# Title\n')")";
assert_contains "heading text preserved"     "${out}" "Title";
assert_contains "heading style applied"      "${out}" "<H>";

# --- Unordered list ---------------------------------------------------------
out="$(hl "$(printf -- '- item\n')")";
assert_contains "list text preserved"        "${out}" "item";
assert_contains "list marker styled"         "${out}" "<L>";

# --- Ordered list -----------------------------------------------------------
out="$(hl "$(printf '1. first\n')")";
assert_contains "ordered list text preserved" "${out}" "first";
assert_contains "ordered list marker styled"  "${out}" "<L>";

# --- Bold -------------------------------------------------------------------
out="$(hl "$(printf 'a **bold** b\n')")";
assert_contains "bold text preserved"        "${out}" "bold";
assert_contains "surrounding text preserved" "${out}" "a ";
assert_contains "bold style applied"         "${out}" "<B>";

# --- Italic -----------------------------------------------------------------
out="$(hl "$(printf 'a *it* b\n')")";
assert_contains "italic text preserved"      "${out}" "it";
assert_contains "italic style applied"       "${out}" "<I>";

# --- Strikethrough ----------------------------------------------------------
out="$(hl "$(printf 'a ~~gone~~ b\n')")";
assert_contains "strikethrough text preserved" "${out}" "gone";
assert_contains "strikethrough style applied"  "${out}" "<S>";

# --- Inline code ------------------------------------------------------------
out="$(hl "$(printf 'use `code` now\n')")";
assert_contains "inline code text preserved" "${out}" "code";
assert_contains "inline code style applied"  "${out}" "<C>";

# --- Link -------------------------------------------------------------------
out="$(hl "$(printf '[text](http://x)\n')")";
assert_contains "link text preserved"        "${out}" "text";
assert_contains "link url preserved"         "${out}" "http://x";
assert_contains "link text style applied"    "${out}" "<LT>";
assert_contains "link url style applied"     "${out}" "<U>";

# --- Plain text is not decorated --------------------------------------------
out="$(hl "$(printf 'plain text\n')")";
assert_contains "plain text preserved"       "${out}" "plain text";
assert_not_contains "no heading style on plain" "${out}" "<H>";
assert_not_contains "no bold style on plain"    "${out}" "<B>";
assert_not_contains "no code style on plain"    "${out}" "<C>";

# --- Fenced code block: Markdown inside is NOT interpreted ------------------
out="$(hl "$(printf '```\n**not bold**\n```\n')")";
assert_contains "code block content preserved"   "${out}" "**not bold**";
assert_not_contains "no bold style inside code block" "${out}" "<B>";
assert_contains "code block style applied"       "${out}" "<CB>";

# --- Escaped markdown -------------------------------------------------------
# A backslash-escaped asterisk should not start bold; the literal * survives.
out="$(hl "$(printf 'a \\* b\n')")";
assert_contains "escaped asterisk survives"  "${out}" "*";
assert_not_contains "escaped asterisk not bold" "${out}" "<B>";

# --- TO_TTY=false is a transparent passthrough ------------------------------
raw="$(printf '# Title with **bold** and `code`\n')";
out="$(printf '%s' "${raw}" | TO_TTY=false bash "${HL}")";
assert_equals "passthrough is byte-for-byte" "${raw}" "${out}";

assert_summary;
