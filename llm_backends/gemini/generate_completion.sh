#!/usr/bin/env bash

# ell_curl (helpers/http.sh), json_* (helpers/json.sh), logging_* and the
# ell_backend_* helpers (helpers/backend_common.sh) are provided by ell.sh,
# which sources the helpers before sourcing this backend.

generate_completion() {
  local line stop_reason;
  # Pass the API key to curl via ELL_CURL_AUTH_HEADER (ell_curl feeds it through
  # a --config file) so it never appears on curl's command line / process table.
  local ELL_CURL_AUTH_HEADER="x-goog-api-key: ${ELL_API_KEY}";
  export ELL_CURL_AUTH_HEADER;

  if [ "x${ELL_API_STREAM}" != "xtrue" ]; then
    ell_backend_nonstreaming "${ELL_API_URL}${ELL_LLM_MODEL}:generateContent" \
      "candidates.0.content.parts.0.text" "candidates.0.finishReason" "STOP" \
      "usageMetadata" "usageMetadata.promptTokenCount" \
      "usageMetadata.candidatesTokenCount" "usageMetadata.totalTokenCount";
    return "${?}";
  fi

  # Streaming: the v1beta endpoint sends one large pretty-printed JSON array,
  # split across many lines. Track JSON object nesting depth while scanning
  # characters once, and json_parse a chunk only when its top-level object
  # closes (depth back to 0) -- rather than re-parsing the whole accumulated
  # buffer per line, which is O(n^2). Strings/escapes are honoured so braces
  # inside text do not affect the depth.
  local curl_pipe_status stream_status;
  ell_curl "${ELL_API_URL}${ELL_LLM_MODEL}:streamGenerateContent" \
    --header "Content-Type: application/json" \
    --data-binary @- | {
    BUFFER="";
    depth=0;
    in_string=false;
    escaped=false;
    received=0;
    emitted=0;
    unparsable=0;
    bad_stop=0;
    prompt_tokens="";
    completion_tokens="";
    total_tokens="";

    # _gemini_emit_chunk: parse BUFFER (one complete JSON object) and emit its
    # text / track finish reason and usage. Sets bad_stop and returns 1 on a
    # non-STOP finish reason so the caller can stop.
    _gemini_emit_chunk() {
      if ! json_parse "${BUFFER}"; then
        logging_debug "Unexpected chunk: ${BUFFER}";
        unparsable=1;
        return 0;
      fi
      if json_has "candidates.0.content.parts.0.text"; then
        json_get "candidates.0.content.parts.0.text";
        emitted=1;
      fi
      if json_has "usageMetadata"; then
        prompt_tokens=$(json_get "usageMetadata.promptTokenCount");
        completion_tokens=$(json_get "usageMetadata.candidatesTokenCount");
        total_tokens=$(json_get "usageMetadata.totalTokenCount");
      fi
      if json_has "candidates.0.finishReason"; then
        stop_reason=$(json_get "candidates.0.finishReason");
        if [ "x${stop_reason}" != "xSTOP" ]; then
          logging_error "Unexpected stop reason: ${stop_reason}";
          bad_stop=1;
          return 1;
        fi
      fi
      return 0;
    }

    while IFS= read -r line; do
      # Strip CR with a bash builtin instead of `echo | tr` (a fork per line).
      line="${line//$'\r'/}";
      received=1;

      # Scan the line character by character, tracking string state and brace
      # depth; accumulate into BUFFER only while inside an object (depth >= 1),
      # so array punctuation ('[', ',', ']', whitespace) is skipped.
      i=0;
      len="${#line}";
      while [ "${i}" -lt "${len}" ]; do
        ch="${line:${i}:1}";
        i=$((i + 1));

        if [ "${depth}" -ge 1 ]; then
          BUFFER="${BUFFER}${ch}";
        fi

        if [ "x${in_string}" = "xtrue" ]; then
          if [ "x${escaped}" = "xtrue" ]; then
            escaped=false;
          elif [ "x${ch}" = 'x\' ]; then
            escaped=true;
          elif [ "x${ch}" = 'x"' ]; then
            in_string=false;
          fi
          continue;
        fi

        case "${ch}" in
          '"')
            in_string=true;
            ;;
          '{')
            if [ "${depth}" -eq 0 ]; then
              BUFFER="{";
            fi
            depth=$((depth + 1));
            ;;
          '}')
            depth=$((depth - 1));
            if [ "${depth}" -eq 0 ]; then
              _gemini_emit_chunk || break;
              BUFFER="";
            fi
            ;;
        esac
      done
      if [ "${bad_stop}" -ne 0 ]; then
        break;
      fi
    done
    logging_debug "Buffer: ${BUFFER}";
    if [ "${emitted}" -ne 0 ]; then
      echo '';
      logging_info "usage: prompt_tokens=${prompt_tokens}, completion_tokens=${completion_tokens}, total_tokens=${total_tokens}";
    fi
    ell_backend_report_stream_end "${emitted}" "${received}" "${unparsable}" "${bad_stop}" "${ELL_API_URL}";
  }
  # Capture the whole PIPESTATUS array at once: any later command resets it.
  local ps=("${PIPESTATUS[@]}");
  curl_pipe_status="${ps[0]}";
  stream_status="${ps[1]}";
  ell_backend_check_pipestatus "${curl_pipe_status}" "${stream_status}";
  return "${?}";
}

export -f generate_completion;
