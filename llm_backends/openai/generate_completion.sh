#!/usr/bin/env bash

# ell_curl (helpers/http.sh), json_* (helpers/json.sh), logging_* and the
# ell_backend_* helpers (helpers/backend_common.sh) are provided by ell.sh,
# which sources the helpers before sourcing this backend.

generate_completion() {
  local line json_chunk stop_reason;
  # Pass the API key to curl via ELL_CURL_AUTH_HEADER (ell_curl feeds it through
  # a --config file) so it never appears on curl's command line / process table.
  local ELL_CURL_AUTH_HEADER="Authorization: Bearer ${ELL_API_KEY}";
  export ELL_CURL_AUTH_HEADER;

  if [ "x${ELL_API_STREAM}" != "xtrue" ]; then
    ell_backend_nonstreaming "${ELL_API_URL}" \
      "choices.0.message.content" "choices.0.finish_reason" "stop" \
      "usage" "usage.prompt_tokens" "usage.completion_tokens" "usage.total_tokens";
    return "${?}";
  fi

  # Streaming: OpenAI uses SSE framing, one JSON object per "data: {...}" line.
  local curl_pipe_status stream_status;
  ell_curl "${ELL_API_URL}" \
    --header "Content-Type: application/json" \
    --data-binary @- | {
    # Track whether the response carried any data chunks at all, whether any was
    # unparsable, and whether we emitted content, so end-of-stream reporting can
    # be specific instead of silently producing nothing.
    received=0;
    emitted=0;
    unparsable=0;
    bad_stop=0;
    prompt_tokens="";
    completion_tokens="";
    total_tokens="";
    while read -r line; do
      if [ "x${line}" = "xdata: [DONE]" ]; then
        break;
      elif [[ "${line}" == "data: {"* ]]; then
        # Data chunk. Use bash builtins (pattern match + prefix strip) instead of
        # `echo | grep` / `echo | cut`, which forked two subprocesses per chunk.
        received=1;
        json_chunk="${line#data: }";
        if ! json_parse "${json_chunk}"; then
          logging_debug "Unexpected chunk: ${json_chunk}";
          unparsable=1;
          continue;
        fi
        if json_has "choices.0.delta.content"; then
          json_get "choices.0.delta.content";
          emitted=1;
        else
          # The finish reason lives at choices.0.finish_reason (null on every
          # intermediate chunk, set to stop/length/content_filter/... on the
          # final one).
          if json_has "choices.0.finish_reason"; then
            stop_reason=$(json_get "choices.0.finish_reason");
            if [ "x${stop_reason}" != "xstop" ]; then
              logging_error "Unexpected stop reason: ${stop_reason}";
              bad_stop=1;
            fi
            break;
          elif json_has "usage"; then
            # Usually the last chunk carries usage information.
            prompt_tokens=$(json_get "usage.prompt_tokens");
            completion_tokens=$(json_get "usage.completion_tokens");
            total_tokens=$(json_get "usage.total_tokens");
            echo '';
            logging_info "usage: prompt_tokens=${prompt_tokens}, completion_tokens=${completion_tokens}, total_tokens=${total_tokens}";
          fi
        fi
      elif [ -z "${line}" ]; then
        continue;
      else
        logging_debug "Unexpected line: ${line}";
        continue;
      fi
    done
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
