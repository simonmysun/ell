#!/usr/bin/env bash

. "$(dirname "${BASH_SOURCE[0]}")/../http.sh";

generate_completion() {
  local response curl_status prompt_tokens completion_tokens total_tokens line stop_reason;
  if [ "x${ELL_API_STREAM}" != "xtrue" ]; then
    logging_debug "Streaming disabled";
    response=$(ell_curl "${ELL_API_URL}${ELL_LLM_MODEL}:generateContent" \
      --header "Content-Type: application/json" \
      --header "x-goog-api-key: ${ELL_API_KEY}" \
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
      --header "x-goog-api-key: ${ELL_API_KEY}" \
      --data-binary @- | {
      # gemni API v1beta sends a large JSON array as chunks. Here we skip the first '[' and expect the in coming chunks to be valid JSON objects until the last line;
      read -N 1;
      PART_FINISHED=false;
      BUFFER="";
      received=0;
      emitted=0;
      bad_stop=0;
      while read -r line; do
        # Strip CR with a bash builtin instead of `echo | tr`, which forked a
        # subprocess for every streamed line.
        line="${line//$'\r'/}";
        received=1;
        if [ "x${PART_FINISHED}" = "xtrue" ] && [ "x${line}" = "x]" ]; then
          logging_debug "End of stream";
          break;
        elif [ "x${PART_FINISHED}" = "xtrue" ] && [ "x${line}" = "x," ]; then
          logging_debug "skip comma";
          continue;
        elif [ "x${PART_FINISHED}" = "xtrue" ]; then
          PART_FINISHED=false;
          BUFFER="${line}";
        else
          BUFFER="${BUFFER}${line}";
          # trying to parse the buffer as JSON
          if json_parse "${BUFFER}"; then
            if json_has "candidates.0.content.parts.0.text"; then
              json_get "candidates.0.content.parts.0.text";
              emitted=1;
            fi
            if json_has "candidates.0.finishReason"; then
              stop_reason=$(json_get "candidates.0.finishReason");
              if [ "x${stop_reason}" != "xSTOP" ]; then
                logging_error "Unexpected stop reason: ${stop_reason}";
                bad_stop=1;
                break;
              fi
            fi
            # check if usageMetadata is present, gemini API v1beta sends usageMetadata in every chunk
            if json_has "usageMetadata"; then
              prompt_tokens=$(json_get "usageMetadata.promptTokenCount");
              completion_tokens=$(json_get "usageMetadata.candidatesTokenCount");
              total_tokens=$(json_get "usageMetadata.totalTokenCount");
            fi
            PART_FINISHED=true;
            BUFFER="";
          fi
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
