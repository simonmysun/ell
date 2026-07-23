#!/usr/bin/env bash

# Pure-bash JSON parser used to replace the external `jq` dependency.
#
# It implements a small recursive-descent parser that tokenises a JSON
# document and lets callers query values by a dotted / indexed path such as
# `choices.0.message.content` or `usage.prompt_tokens`.
#
# Only the subset of JSON needed by the LLM backends is required, but the
# parser handles the full grammar (objects, arrays, strings with escapes,
# numbers, booleans and null) so it stays correct on arbitrary API responses.
#
# Public functions:
#   json_parse <json-text>
#       Parse a document once. Results are stored in the associative array
#       `JSON` keyed by path. Returns non-zero if the text is not valid JSON.
#
#   json_get <path>
#       Print the decoded value stored at <path> from the last json_parse.
#       Returns non-zero if the path is absent.
#
#   json_has <path>
#       Return zero (success) if <path> exists and is not JSON null.
#
#   json_is_valid <json-text>
#       Return zero if <json-text> is a complete, valid JSON document.
#
# The parser stores fully decoded string values (escape sequences and
# \uXXXX sequences are turned into their UTF-8 bytes), so callers get the
# same output that `jq -r` produced previously.

# Internal parser state.
declare -A JSON=();      # path -> decoded scalar value
declare -A JSON_TYPE=(); # path -> type: object|array|string|number|bool|null
_JSON_S="";              # the input string being parsed
_JSON_I=0;               # current index into _JSON_S
_JSON_N=0;               # length of _JSON_S

# _json_error: record failure position for debugging and return non-zero.
_json_error() {
  _JSON_ERR="${1} at offset ${_JSON_I}";
  return 1;
}

# _json_skip_ws: advance the cursor past insignificant whitespace.
_json_skip_ws() {
  local c;
  while [ "${_JSON_I}" -lt "${_JSON_N}" ]; do
    c="${_JSON_S:${_JSON_I}:1}";
    case "${c}" in
      ' '|$'\t'|$'\n'|$'\r') _JSON_I=$((_JSON_I + 1)); ;;
      *) break; ;;
    esac
  done
}

# _json_parse_string: parse a JSON string starting at the opening quote and
# leave the fully decoded value in _JSON_STR. Advances the cursor past the
# closing quote.
_json_parse_string() {
  local out="" c hex code
  # Skip the opening quote.
  _JSON_I=$((_JSON_I + 1));
  while [ "${_JSON_I}" -lt "${_JSON_N}" ]; do
    c="${_JSON_S:${_JSON_I}:1}";
    if [ "${c}" = '"' ]; then
      _JSON_I=$((_JSON_I + 1));
      _JSON_STR="${out}";
      return 0;
    elif [ "${c}" = '\' ]; then
      _JSON_I=$((_JSON_I + 1));
      c="${_JSON_S:${_JSON_I}:1}";
      case "${c}" in
        '"') out="${out}\""; _JSON_I=$((_JSON_I + 1)); ;;
        '\') out="${out}\\"; _JSON_I=$((_JSON_I + 1)); ;;
        '/') out="${out}/"; _JSON_I=$((_JSON_I + 1)); ;;
        b) out="${out}"$'\b'; _JSON_I=$((_JSON_I + 1)); ;;
        f) out="${out}"$'\f'; _JSON_I=$((_JSON_I + 1)); ;;
        n) out="${out}"$'\n'; _JSON_I=$((_JSON_I + 1)); ;;
        r) out="${out}"$'\r'; _JSON_I=$((_JSON_I + 1)); ;;
        t) out="${out}"$'\t'; _JSON_I=$((_JSON_I + 1)); ;;
        u)
          hex="${_JSON_S:$((_JSON_I + 1)):4}";
          if [ "${#hex}" -ne 4 ]; then
            _json_error "truncated \\u escape";
            return 1;
          fi
          code=$((16#${hex}));
          _JSON_I=$((_JSON_I + 5));
          # Handle UTF-16 surrogate pairs.
          if [ "${code}" -ge 55296 ] && [ "${code}" -le 56319 ]; then
            if [ "${_JSON_S:${_JSON_I}:2}" = '\u' ]; then
              local hex2 lo
              hex2="${_JSON_S:$((_JSON_I + 2)):4}";
              lo=$((16#${hex2}));
              _JSON_I=$((_JSON_I + 6));
              code=$(( (code - 55296) * 1024 + (lo - 56320) + 65536 ));
            fi
          fi
          # Convert the code point to UTF-8 bytes and append them to out.
          # Using printf -v (rather than command substitution) preserves
          # bytes that would otherwise be stripped, such as \u000a (newline).
          _json_codepoint_to_utf8 "${code}";
          out="${out}${_JSON_UTF8}";
          ;;
        *)
          _json_error "invalid escape \\${c}";
          return 1;
          ;;
      esac
    else
      out="${out}${c}";
      _JSON_I=$((_JSON_I + 1));
    fi
  done
  _json_error "unterminated string";
  return 1;
}

# _json_codepoint_to_utf8: encode a Unicode code point as UTF-8 and leave the
# resulting bytes in _JSON_UTF8. The result is built with printf -v so that
# no bytes (including newline / carriage return) are lost.
_json_codepoint_to_utf8() {
  local code="${1}" esc;
  _JSON_UTF8="";
  if [ "${code}" -eq 0 ]; then
    # A literal NUL cannot be represented in a bash string; emit nothing.
    return 0;
  fi
  # Build a string of \xHH escapes, then let printf decode it into raw bytes.
  # printf -v keeps every byte, including newline (0x0a) and CR (0x0d) that
  # command substitution would strip.
  if [ "${code}" -lt 128 ]; then
    printf -v esc '\\x%02x' "${code}";
  elif [ "${code}" -lt 2048 ]; then
    printf -v esc '\\x%02x\\x%02x' \
      $(( (code >> 6) | 192 )) \
      $(( (code & 63) | 128 ));
  elif [ "${code}" -lt 65536 ]; then
    printf -v esc '\\x%02x\\x%02x\\x%02x' \
      $(( (code >> 12) | 224 )) \
      $(( ((code >> 6) & 63) | 128 )) \
      $(( (code & 63) | 128 ));
  else
    printf -v esc '\\x%02x\\x%02x\\x%02x\\x%02x' \
      $(( (code >> 18) | 240 )) \
      $(( ((code >> 12) & 63) | 128 )) \
      $(( ((code >> 6) & 63) | 128 )) \
      $(( (code & 63) | 128 ));
  fi
  printf -v _JSON_UTF8 '%b' "${esc}";
}

# _json_parse_literal: parse true, false or null starting at the cursor.
_json_parse_literal() {
  local path="${1}";
  if [ "${_JSON_S:${_JSON_I}:4}" = "true" ]; then
    JSON["${path}"]="true"; JSON_TYPE["${path}"]="bool";
    _JSON_I=$((_JSON_I + 4));
    return 0;
  elif [ "${_JSON_S:${_JSON_I}:5}" = "false" ]; then
    JSON["${path}"]="false"; JSON_TYPE["${path}"]="bool";
    _JSON_I=$((_JSON_I + 5));
    return 0;
  elif [ "${_JSON_S:${_JSON_I}:4}" = "null" ]; then
    JSON["${path}"]=""; JSON_TYPE["${path}"]="null";
    _JSON_I=$((_JSON_I + 4));
    return 0;
  fi
  _json_error "invalid literal";
  return 1;
}

# _json_parse_number: parse a number token starting at the cursor.
# The candidate run of number characters is scanned first, then validated
# against the JSON number grammar (RFC 8259):
#   number = [ "-" ] int [ frac ] [ exp ]
#   int    = "0" | ( digit1-9 *digit )
#   frac   = "." 1*digit
#   exp    = ("e" | "E") ["+" | "-"] 1*digit
# so malformed tokens such as 1+2, 1.2.3, 1e, 1., 00 or 01 are rejected.
_json_parse_number() {
  local path="${1}";
  local start="${_JSON_I}" c token;
  while [ "${_JSON_I}" -lt "${_JSON_N}" ]; do
    c="${_JSON_S:${_JSON_I}:1}";
    case "${c}" in
      [0-9]|-|+|.|e|E) _JSON_I=$((_JSON_I + 1)); ;;
      *) break; ;;
    esac
  done
  token="${_JSON_S:${start}:$((_JSON_I - start))}";
  if [[ ! "${token}" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]]; then
    _json_error "invalid number '${token}'";
    return 1;
  fi
  JSON["${path}"]="${token}";
  JSON_TYPE["${path}"]="number";
  return 0;
}

# _JSON_ROOT: sentinel key used for the document root value. bash associative
# arrays cannot use an empty subscript, so the empty path maps to this key.
_JSON_ROOT=$'\001root';

# _json_key: translate a logical path ("" for root) into a storage key.
_json_key() {
  if [ -z "${1}" ]; then
    printf '%s' "${_JSON_ROOT}";
  else
    printf '%s' "${1}";
  fi
}

# _json_parse_value: dispatch on the next token and parse a value into <path>.
_json_parse_value() {
  local path key c;
  path="${1}";
  key="$(_json_key "${path}")";
  _json_skip_ws;
  if [ "${_JSON_I}" -ge "${_JSON_N}" ]; then
    _json_error "unexpected end of input";
    return 1;
  fi
  c="${_JSON_S:${_JSON_I}:1}";
  case "${c}" in
    '{') _json_parse_object "${path}" "${key}"; return "${?}"; ;;
    '[') _json_parse_array "${path}" "${key}"; return "${?}"; ;;
    '"')
      if ! _json_parse_string; then return 1; fi
      JSON["${key}"]="${_JSON_STR}"; JSON_TYPE["${key}"]="string";
      return 0;
      ;;
    t|f|n) _json_parse_literal "${key}"; return "${?}"; ;;
    -|[0-9]) _json_parse_number "${key}"; return "${?}"; ;;
    *) _json_error "unexpected character '${c}'"; return 1; ;;
  esac
}

# _json_parse_object: parse an object into <path> (storage key <key>) and its
# members.
_json_parse_object() {
  local path="${1}" key="${2}" child mkey c;
  JSON["${key}"]="[object]"; JSON_TYPE["${key}"]="object";
  _JSON_I=$((_JSON_I + 1)); # skip '{'
  _json_skip_ws;
  if [ "${_JSON_S:${_JSON_I}:1}" = '}' ]; then
    _JSON_I=$((_JSON_I + 1));
    return 0;
  fi
  while true; do
    _json_skip_ws;
    if [ "${_JSON_S:${_JSON_I}:1}" != '"' ]; then
      _json_error "expected object key";
      return 1;
    fi
    if ! _json_parse_string; then return 1; fi
    mkey="${_JSON_STR}";
    _json_skip_ws;
    if [ "${_JSON_S:${_JSON_I}:1}" != ':' ]; then
      _json_error "expected ':'";
      return 1;
    fi
    _JSON_I=$((_JSON_I + 1));
    if [ -z "${path}" ]; then
      child="${mkey}";
    else
      child="${path}.${mkey}";
    fi
    if ! _json_parse_value "${child}"; then return 1; fi
    _json_skip_ws;
    c="${_JSON_S:${_JSON_I}:1}";
    if [ "${c}" = ',' ]; then
      _JSON_I=$((_JSON_I + 1));
      continue;
    elif [ "${c}" = '}' ]; then
      _JSON_I=$((_JSON_I + 1));
      return 0;
    else
      _json_error "expected ',' or '}'";
      return 1;
    fi
  done
}

# _json_parse_array: parse an array into <path> (storage key <key>) and its
# indexed elements. The element count is stored under "<key>.length".
_json_parse_array() {
  local path="${1}" key="${2}" idx=0 child c;
  JSON["${key}"]="[array]"; JSON_TYPE["${key}"]="array";
  _JSON_I=$((_JSON_I + 1)); # skip '['
  _json_skip_ws;
  if [ "${_JSON_S:${_JSON_I}:1}" = ']' ]; then
    _JSON_I=$((_JSON_I + 1));
    JSON["${key}.length"]="0";
    return 0;
  fi
  while true; do
    if [ -z "${path}" ]; then
      child="${idx}";
    else
      child="${path}.${idx}";
    fi
    if ! _json_parse_value "${child}"; then return 1; fi
    idx=$((idx + 1));
    _json_skip_ws;
    c="${_JSON_S:${_JSON_I}:1}";
    if [ "${c}" = ',' ]; then
      _JSON_I=$((_JSON_I + 1));
      continue;
    elif [ "${c}" = ']' ]; then
      _JSON_I=$((_JSON_I + 1));
      JSON["${key}.length"]="${idx}";
      return 0;
    else
      _json_error "expected ',' or ']'";
      return 1;
    fi
  done
}

# json_parse: entry point. Parse <json-text> and populate JSON / JSON_TYPE.
json_parse() {
  JSON=();
  JSON_TYPE=();
  _JSON_S="${1}";
  _JSON_I=0;
  _JSON_N="${#_JSON_S}";
  _JSON_ERR="";
  if ! _json_parse_value ""; then
    return 1;
  fi
  _json_skip_ws;
  # Trailing content after a complete value means the document is malformed.
  if [ "${_JSON_I}" -lt "${_JSON_N}" ]; then
    _json_error "trailing content";
    return 1;
  fi
  return 0;
}

# json_get: print the value at <path>, or return non-zero if missing.
json_get() {
  local key;
  key="$(_json_key "${1}")";
  if [ -z "${JSON_TYPE[${key}]+x}" ]; then
    return 1;
  fi
  printf '%s' "${JSON[${key}]}";
  return 0;
}

# json_has: succeed if <path> exists and is not null.
json_has() {
  local key;
  key="$(_json_key "${1}")";
  if [ -z "${JSON_TYPE[${key}]+x}" ]; then
    return 1;
  fi
  if [ "${JSON_TYPE[${key}]}" = "null" ]; then
    return 1;
  fi
  return 0;
}

# json_is_valid: succeed if <json-text> is a complete, valid JSON document.
json_is_valid() {
  json_parse "${1}" >/dev/null 2>&1;
}

export -f json_parse json_get json_has json_is_valid 2>/dev/null;
export -f _json_parse_value _json_parse_object _json_parse_array 2>/dev/null;
export -f _json_parse_string _json_parse_number _json_parse_literal 2>/dev/null;
export -f _json_skip_ws _json_codepoint_to_utf8 _json_error _json_key 2>/dev/null;
