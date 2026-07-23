#!/usr/bin/env bash

generate_completion() {
  local response curl_status prompt_tokens completion_tokens total_tokens line json_chunk stop_reason;
  if [ "x${ELL_API_STREAM}" != "xtrue" ]; then
    logging_debug "Streaming disabled";
    response=$(cat - | curl "${ELL_API_URL}" \
      --silent \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer ${ELL_API_KEY}" \
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
      # check if finish_reason is present
      if json_has "choices.0.finish_reason"; then
        if [ "x$(json_get "choices.0.finish_reason")" != "xstop" ]; then
          logging_error "Unexpected finish reason: $(json_get "choices.0.finish_reason")";
          return 1;
        else
          json_get "choices.0.message.content";
          echo "";
          if json_has "usage"; then
            prompt_tokens=$(json_get "usage.prompt_tokens");
            completion_tokens=$(json_get "usage.completion_tokens");
            total_tokens=$(json_get "usage.total_tokens");
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
    curl "${ELL_API_URL}" \
      --silent \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer ${ELL_API_KEY}" \
      --data-binary @- | {
      # Track whether the response carried any data chunks at all, and whether
      # we managed to emit any content. This lets us report a clear error
      # instead of silently producing nothing when the response is malformed.
      received=0;
      emitted=0;
      unparsable=0;
      while read -r line; do
        if [ "x${line}" = "xdata: [DONE]" ]; then
          # End of stream
          break;
        elif echo "x${line}" | grep -e "^xdata: {" > /dev/null 2>&1; then
          # Data chunk received
          received=1;
          json_chunk=$(echo "${line}" | cut -c 6-);
          if ! json_parse "${json_chunk}"; then
            logging_debug "Unexpected chunk: ${json_chunk}";
            unparsable=1;
            continue;
          fi
          if json_has "choices.0.delta.content"; then
            json_get "choices.0.delta.content";
            emitted=1;
          else
            if json_has "finish_reason"; then
              stop_reason=$(json_get "finish_reason");
              if [ "x${stop_reason}" != "xstop" ]; then
                logging_error "Unexpected stop reason: ${stop_reason}";
              fi
              break;
            elif json_has "usage"; then
              # Data chunk contains usage information (This is usually the last chunk)
              prompt_tokens=$(json_get "usage.prompt_tokens");
              completion_tokens=$(json_get "usage.completion_tokens");
              total_tokens=$(json_get "usage.total_tokens");
              echo '';
              logging_info "usage: prompt_tokens=${prompt_tokens}, completion_tokens=${completion_tokens}, total_tokens=${total_tokens}";
            fi
          fi
        elif [ -z "${line}" ]; then
          # Empty line, skip
          continue;
        else
          logging_debug "Unexpected line: ${line}";
          continue;
        fi
      done
      # Report a failure (via exit status) if the stream produced no usable
      # content, so the caller does not silently succeed with empty output.
      if [ "${emitted}" -eq 0 ]; then
        if [ "${received}" -eq 0 ]; then
          logging_error "No data received from ${ELL_API_URL} (empty or non-streaming response)";
        elif [ "${unparsable}" -ne 0 ]; then
          logging_error "Response could not be parsed as a valid streaming completion";
        else
          logging_error "Streaming response contained no content";
        fi
        exit 3;
      fi
    }
    # Capture the whole PIPESTATUS array at once: any later simple command
    # (including an assignment) resets it.
    local ps=("${PIPESTATUS[@]}");
    curl_pipe_status="${ps[0]}";
    stream_status="${ps[1]}";
    # Check if curl was successful
    if [ "${curl_pipe_status}" -ne 0 ]; then
      logging_fatal "Failed to generate completion: curl exited with ${curl_pipe_status}";
      return 1;
    fi
    if [ "${stream_status}" -ne 0 ]; then
      return 1;
    fi
  fi
}

export generate_completion;
