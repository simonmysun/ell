#!/usr/bin/env bash

function generate_completion() {
  if [[ x$ELL_API_STREAM == "xfalse" ]]; then
    logging_debug "Streaming disabled";
    response=$(cat - | curl "${ELL_API_URL}${ELL_LLM_MODEL}:generateContent" \
      --silent \
      --header "Content-Type: application/json" \
      --header "x-goog-api-key: ${ELL_API_KEY}" \
      --data-binary @-);
    if [ $? -ne 0 ]; then
      logging_fatal "Failed to generate completion";
      logging_debug "Response: ${response}";
      exit 1;
    else
      if (echo ${response} | jq -e '.candidates[0].finishReason' > /dev/null); then
        if [[ "x$(echo ${response} | jq -r '.candidates[0].finishReason')" != "xSTOP" ]]; then
          logging_error "Unexpected finish reason: $(echo ${response} | jq -r '.choices[0].finish_reason')";
        else
          echo ${response} | jq -j -r '.candidates[0].content.parts[0].text';
          echo "";
          if (echo ${response} | jq -e -r '.usageMetadata' > /dev/null); then
            prompt_tokens=$(echo ${response} | jq -j -r '.usageMetadata.promptTokenCount');
            completion_tokens=$(echo ${response} | jq -j -r '.usageMetadata.candidatesTokenCount');
            total_tokens=$(echo ${response} | jq -j -r '.usageMetadata.totalTokenCount');
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
      read -N 1;
      PART_FINISHED=false;
      BUFFER="";
      while read -r line; do
        line=$(echo ${line} | tr -d '\r');
        if [[ ${PART_FINISHED} == true && "x${line}" == "x]" ]]; then
          logging_debug "End of stream";
          break;
        elif [[ ${PART_FINISHED} == true && "x${line}" == "x," ]]; then
          logging_debug "skip comma";
          continue;
        elif [[ ${PART_FINISHED} == true ]]; then
          PART_FINISHED=false;
          BUFFER="${line}";
        else
          BUFFER="${BUFFER}${line}";
          if jq -e . >/dev/null 2>&1 <<<"${BUFFER}"; then
            json_chunk=$(echo "${line}" | cut -c 6-);
            if (echo ${BUFFER} | jq -e -r '.candidates[0].content.parts[0].text' > /dev/null); then
              echo ${BUFFER} | jq -j -r '.candidates[0].content.parts[0].text';
            fi
            if (echo ${BUFFER} | jq -e -r '.candidates[0].finishReason' > /dev/null); then
              stop_reason=$(echo ${BUFFER} | jq -j -r '.candidates[0].finishReason');
              if [[ "x${stop_reason}" != "xSTOP" ]]; then
                logging_error "Unexpected stop reason: ${stop_reason}";
                break;
              fi
            fi
            if (echo ${BUFFER} | jq -e -r '.usageMetadata' > /dev/null); then
              prompt_tokens=$(echo ${BUFFER} | jq -j -r '.usageMetadata.promptTokenCount');
              completion_tokens=$(echo ${BUFFER} | jq -j -r '.usageMetadata.candidatesTokenCount');
              total_tokens=$(echo ${BUFFER} | jq -j -r '.usageMetadata.totalTokenCount');
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
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
      logging_fatal "Failed to generate completion";
      exit 1;
    fi
  fi
}

export -f generate_completion;