#!/usr/bin/env bash

generate_completion() {
  local response curl_status prompt_tokens completion_tokens total_tokens line stop_reason;
  if [ "x${ELL_API_STREAM}" != "xtrue" ]; then
    logging_debug "Streaming disabled";
    response=$(cat - | curl "${ELL_API_URL}${ELL_LLM_MODEL}:generateContent" \
      --silent \
      --header "Content-Type: application/json" \
      --header "x-goog-api-key: ${ELL_API_KEY}" \
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
      # check if finishReason is present
      if json_has "candidates.0.finishReason"; then
        if [ "x$(json_get "candidates.0.finishReason")" != "xSTOP" ]; then
          logging_error "Unexpected finish reason: $(json_get "candidates.0.finishReason")";
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
      fi
    fi
  else
    prompt_tokens="";
    completion_tokens=""
    total_tokens="";
    curl "${ELL_API_URL}${ELL_LLM_MODEL}:streamGenerateContent" \
      --silent \
      --header "Content-Type: application/json" \
      --header "x-goog-api-key: ${ELL_API_KEY}" \
      --data-binary @- | {
      # gemni API v1beta sends a large JSON array as chunks. Here we skip the first '[' and expect the in coming chunks to be valid JSON objects until the last line;
      read -N 1;
      PART_FINISHED=false;
      BUFFER="";
      while read -r line; do
        line=$(echo "${line}" | tr -d '\r');
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
            fi
            if json_has "candidates.0.finishReason"; then
              stop_reason=$(json_get "candidates.0.finishReason");
              if [ "x${stop_reason}" != "xSTOP" ]; then
                logging_error "Unexpected stop reason: ${stop_reason}";
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
    }
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      logging_fatal "Failed to generate completion";
      exit 1;
    fi
  fi
}

export generate_completion;
