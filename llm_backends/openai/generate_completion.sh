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
      exit 1;
    else
      if ! json_parse "${response}"; then
        logging_error "Unexpected format: ${response}";
        return 1;
      fi
      # check if finish_reason is present
      if json_has "choices.0.finish_reason"; then
        if [ "x$(json_get "choices.0.finish_reason")" != "xstop" ]; then
          logging_error "Unexpected finish reason: $(json_get "choices.0.finish_reason")";
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
      fi
    fi
  else
    curl "${ELL_API_URL}" \
      --silent \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer ${ELL_API_KEY}" \
      --data-binary @- | {
      while read -r line; do
        if [ "x${line}" = "xdata: [DONE]" ]; then
          # End of stream
          break;
        elif echo "x${line}" | grep -e "^xdata: {" > /dev/null 2>&1; then
          # Data chunk received
          json_chunk=$(echo "${line}" | cut -c 6-);
          if ! json_parse "${json_chunk}"; then
            logging_debug "Unexpected chunk: ${json_chunk}";
            continue;
          fi
          if json_has "choices.0.delta.content"; then
            json_get "choices.0.delta.content";
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
    }
    # Check if curl was successful
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      logging_fatal "Failed to generate completion: ${PIPESTATUS[0]}";
      exit 1;
    fi
  fi
}

export generate_completion;
