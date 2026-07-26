#!/usr/bin/env bash

. "$(dirname "${BASH_SOURCE[0]}")/../http.sh";

generate_completion() {
  local response curl_status prompt_tokens completion_tokens total_tokens line stop_reason;
  # Pass the API key to curl via ELL_CURL_AUTH_HEADER (ell_curl feeds it through
  # a --config file) so it never appears on curl's command line / process table.
  local ELL_CURL_AUTH_HEADER="x-goog-api-key: ${ELL_API_KEY}";
  export ELL_CURL_AUTH_HEADER;
  if [ "x${ELL_API_STREAM}" != "xtrue" ]; then
    logging_debug "Streaming disabled";
    response=$(ell_curl "${ELL_API_URL}${ELL_LLM_MODEL}:generateContent" \
      --header "Content-Type: application/json" \
      --data-binary @-);
    curl_status="${?}";
    # Check if curl was successful
    if [ "${curl_status}" -ne 0 ]; then
      logging_fatal "Failed to generate completion: curl exited with ${curl_status}";
      logging_debug "Response: ${response}";
      return 1;
    else
      if ! json_parse "${response}"; then
        logging_error "Unexpected format: ${response}";
        return 1;
      fi
      # check if finishReason is present
      if json_has "candidates.0.finishReason"; then
        if [ "x$(json_get "candidates.0.finishReason")" != "xSTOP" ]; then
          logging_error "Unexpected finish reason: $(json_get "candidates.0.finishReason")";
          return 1;
        else
          json_get "candidates.0.content.parts.0.text";
          echo "";
          if json_has "usageMetadata"; then
            prompt_tokens=$(json_get "usageMetadata.promptTokenCount");
            completion_tokens=$(json_get "usageMetadata.candidatesTokenCount");
            total_tokens=$(json_get "usageMetadata.totalTokenCount");
            echo '';
            logging_info "usage: prompt_tokens=${prompt_tokens}, completion_tokens=${completion_tokens}, total_tokens=${total_tokens}";
          fi
        fi
      else
        logging_error "Unexpected format: ${response}";
        return 1;
      fi
    fi
  else
    local curl_pipe_status stream_status;
    prompt_tokens="";
    completion_tokens=""
    total_tokens="";
    ell_curl "${ELL_API_URL}${ELL_LLM_MODEL}:streamGenerateContent" \
      --header "Content-Type: application/json" \
      --data-binary @- | {
      # The v1beta streaming endpoint sends one large pretty-printed JSON array,
      # split across many lines. Each array element is a chunk object we want to
      # parse.
      #
      # Rather than re-running json_parse on the whole accumulated buffer after
      # every line (which is O(n^2): a chunk spans dozens of lines and each added
      # line re-parses everything so far), track JSON object nesting depth while
      # scanning characters once, and only json_parse a chunk when its top-level
      # object closes (depth returns to 0). Strings and escapes are honoured so
      # braces inside text do not affect the depth.
      BUFFER="";
      depth=0;
      in_string=false;
      escaped=false;
      received=0;
      emitted=0;
      bad_stop=0;

      # _gemini_emit_chunk: parse BUFFER (one complete JSON object) and emit its
      # text / track finish reason and usage. Sets bad_stop and returns 1 on a
      # non-STOP finish reason so the caller can stop.
      _gemini_emit_chunk() {
        json_parse "${BUFFER}" || return 0;
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
        # Strip CR with a bash builtin instead of `echo | tr`, which forked a
        # subprocess for every streamed line.
        line="${line//$'\r'/}";
        received=1;

        # Scan this line character by character, tracking string state and brace
        # depth. Accumulate characters into BUFFER only while inside an object
        # (depth >= 1), so the surrounding array punctuation ('[', ',', ']',
        # whitespace) is skipped.
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
                # Start of a new top-level object; begin buffering with this '{'.
                BUFFER="{";
              fi
              depth=$((depth + 1));
              ;;
            '}')
              depth=$((depth - 1));
              if [ "${depth}" -eq 0 ]; then
                # A complete top-level object is in BUFFER: parse it once.
                _gemini_emit_chunk || break;
                BUFFER="";
              fi
              ;;
          esac
        done
        # Stop the outer loop too if a bad finish reason was seen.
        if [ "${bad_stop}" -ne 0 ]; then
          break;
        fi
      done
      logging_debug "Buffer: ${BUFFER}";
      echo '';
      logging_info "usage: prompt_tokens=${prompt_tokens}, completion_tokens=${completion_tokens}, total_tokens=${total_tokens}";
      # Report a failure if nothing usable came back, instead of silently
      # succeeding with no output.
      if [ "${emitted}" -eq 0 ]; then
        if [ "${received}" -eq 0 ]; then
          logging_error "No data received from ${ELL_API_URL} (empty response)";
        else
          logging_error "Streaming response contained no content";
        fi
        exit 3;
      fi
      # A non-"STOP" finish reason means the completion was truncated or
      # otherwise abnormal (e.g. MAX_TOKENS, SAFETY). Fail even if some content
      # was emitted, matching the non-streaming path, so a truncated completion
      # is not reported as success.
      if [ "${bad_stop}" -ne 0 ]; then
        exit 4;
      fi
    }
    # Capture the whole PIPESTATUS array at once: any later simple command
    # (including an assignment) resets it.
    local ps=("${PIPESTATUS[@]}");
    curl_pipe_status="${ps[0]}";
    stream_status="${ps[1]}";
    # Preserve the distinct exit codes so callers can tell a curl failure (the
    # curl exit code) from a stream-parse failure (exit 3 from the reader).
    if [ "${curl_pipe_status}" -ne 0 ]; then
      logging_fatal "Failed to generate completion: curl exited with ${curl_pipe_status}";
      return "${curl_pipe_status}";
    fi
    if [ "${stream_status}" -ne 0 ]; then
      return "${stream_status}";
    fi
  fi
}

export -f generate_completion;
