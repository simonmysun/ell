#!/usr/bin/env bash

function generate_completion() {
  if [[ ${ELL_API_STREAM} != true ]]; then
    logging_debug "Streaming disabled";
    response=$(cat - | curl "${ELL_API_URL}" \
      --silent \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer ${ELL_API_KEY}" \
      --data-binary @-);
    if [ $? -ne 0 ]; then
      logging_fatal "Failed to generate completion";
      logging_debug "Response: ${response}";
      exit 1;
    else
      if (echo "${response}" | jq -e '.choices[0].finish_reason' > /dev/null); then
        if [[ $(echo "${response}" | jq -r '.choices[0].finish_reason') != "stop" ]]; then
          logging_error "Unexpected finish reason: $(echo "${response}" | jq -r '.choices[0].finish_reason')";
        else
          echo "${response}" | jq -j -r '.choices[0].message.content';
          echo "";
          if (echo "${response}" | jq -e -r '.usage' > /dev/null); then
            prompt_tokens=$(echo "${response}" | jq -j -r '.usage.prompt_tokens');
            completion_tokens=$(echo "${response}" | jq -j -r '.usage.completion_tokens');
            total_tokens=$(echo "${response}" | jq -j -r '.usage.total_tokens');
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
        if [[ "x${line}" == "xdata: [DONE]" ]]; then
          break;
        elif [[ "x${line}" == "xdata: {"* ]]; then
          json_chunk=$(echo "${line}" | cut -c 6-);
          if (echo "${json_chunk}" | jq -e -r '.choices[0].delta.content' > /dev/null); then
            echo "${json_chunk}" | jq -j -r '.choices[0].delta.content';
          else
            if (echo "${json_chunk}" | jq -e -r '.finish_reason' > /dev/null); then
              stop_reason=$(echo "${json_chunk}" | jq -j -r '.finish_reason');
              if [[ "x${stop_reason}" != "xstop" ]]; then
                logging_error "Unexpected stop reason: ${stop_reason}";
              fi
              break;
            elif (echo "${json_chunk}" | jq -e -r '.usage' > /dev/null); then
              prompt_tokens=$(echo "${json_chunk}" | jq -j -r '.usage.prompt_tokens');
              completion_tokens=$(echo "${json_chunk}" | jq -j -r '.usage.completion_tokens');
              total_tokens=$(echo "${json_chunk}" | jq -j -r '.usage.total_tokens');
              echo '';
              logging_info "usage: prompt_tokens=${prompt_tokens}, completion_tokens=${completion_tokens}, total_tokens=${total_tokens}";
            fi
          fi
        elif [[ -z "${line}" ]]; then
          continue;
        else
          logging_debug "Unexpected line: ${line}";
          continue;
        fi
      done
    }
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
      logging_fatal "Failed to generate completion: ${PIPESTATUS[0]}";
      exit 1;
    fi
  fi
}

export -f generate_completion;