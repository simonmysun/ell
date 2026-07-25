#!/usr/bin/env bash

# Unit tests for helpers/json.sh, the pure-bash JSON parser that replaced jq.
#
# The parser is security- and correctness-sensitive: it runs on arbitrary API
# responses, decodes string escapes and \uXXXX (including surrogate pairs) into
# UTF-8, and validates the full RFC 8259 number grammar. These tests exercise
# path queries, escape/unicode decoding, presence checks and malformed-input
# rejection.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";
. "${DIR}/json.sh";

echo "json tests";
echo "==========";

# --- Path queries -----------------------------------------------------------

json_parse '{"choices":[{"message":{"content":"hello"}}],"usage":{"prompt_tokens":7}}';
assert_equals "nested object path"   "hello" "$(json_get choices.0.message.content)";
assert_equals "nested number path"   "7"     "$(json_get usage.prompt_tokens)";

json_parse '{"data":[10,20,30]}';
assert_equals "array element by index" "20" "$(json_get data.1)";
# NOTE: array lengths are stored in the JSON array under "<path>.length" but the
# parser does not populate JSON_TYPE for them, so they are not reachable through
# the public json_get API (which guards on JSON_TYPE). We therefore assert the
# stored length via the internal array. If json_get is ever fixed to expose
# lengths, switch this to: assert_equals ... "$(json_get data.length)".
assert_equals "array length recorded"  "3"  "${JSON[data.length]}";

json_parse '"just a scalar"';
assert_equals "root scalar via empty path" "just a scalar" "$(json_get '')";

# --- String escape decoding -------------------------------------------------

json_parse '{"s":"a\nb\tc"}';
assert_equals "decodes \\n and \\t" "$(printf 'a\nb\tc')" "$(json_get s)";

json_parse '{"s":"quote:\" slash:\/ back:\\"}';
assert_equals "decodes quote/slash/backslash" 'quote:" slash:/ back:\' "$(json_get s)";

# --- Unicode decoding -------------------------------------------------------

json_parse '{"s":"\u4f60\u597d"}';
assert_equals "decodes BMP \\u escapes to UTF-8" "你好" "$(json_get s)";

json_parse '{"s":"\ud83d\ude00"}';
assert_equals "decodes surrogate pair to emoji" "😀" "$(json_get s)";

# --- Presence / null semantics ----------------------------------------------

json_parse '{"present":1,"empty":"","nothing":null}';
assert_success  "json_has true for present key"  json_has present;
assert_success  "json_has true for empty string" json_has empty;
assert_failure  "json_has false for null value"  json_has nothing;
assert_failure  "json_has false for missing key" json_has does_not_exist;
assert_failure  "json_get fails on missing key"  json_get does_not_exist;

# --- Validity: well-formed documents accepted -------------------------------

assert_success "valid object"        json_is_valid '{"a":1,"b":[true,false,null]}';
assert_success "valid nested array"  json_is_valid '[[1],[2,3],[]]';
assert_success "valid number forms"  json_is_valid '{"a":-1.5e10,"b":0,"c":1.25}';

# --- Validity: malformed documents rejected ---------------------------------

assert_failure "rejects bare word"        json_is_valid '{bad}';
assert_failure "rejects trailing comma"   json_is_valid '{"a":1,}';
assert_failure "rejects trailing content" json_is_valid '{"a":1} extra';
assert_failure "rejects leading zero"     json_is_valid '01';
assert_failure "rejects bare dot number"  json_is_valid '1.';
assert_failure "rejects incomplete exp"   json_is_valid '1e';
assert_failure "rejects unterminated str" json_is_valid '{"a":"oops}';
assert_failure "rejects empty input"      json_is_valid '';

# --- Long / mixed string values (exercise the bulk-copy fast path) ----------
# The string parser copies runs of ordinary characters in one operation rather
# than one character at a time. These cases guard that the fast path preserves
# long values and still interleaves escapes / unicode correctly.

# A long run of ordinary characters round-trips intact.
long="$(printf 'a%.0s' $(seq 1 2000))";
assert_success "parses a long plain string" json_parse "{\"s\":\"${long}\"}";
assert_equals  "long plain string preserved" "${long}" "$(json_get s)";

# Ordinary runs interleaved with escapes and a surrogate-pair emoji.
assert_success "parses mixed string" \
  json_parse '{"t":"hi \"q\" \u0041 \n x \ud83d\ude00 end"}';
assert_equals  "mixed string decoded correctly" \
  "$(printf 'hi "q" A \n x \360\237\230\200 end')" "$(json_get t)";

# A string that begins immediately with an escape (empty leading ordinary run).
assert_success "parses leading-escape string" json_parse '{"t":"\n after"}';
assert_equals  "leading-escape decoded" "$(printf '\n after')" "$(json_get t)";

assert_summary;
