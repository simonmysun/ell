#!/usr/bin/env bash

# Shared logic for the LLM backends.
#
# The openai and gemini backends differ only in their streaming parsers (SSE
# line framing vs a single pretty-printed JSON array) and in a handful of
# provider-specific JSON paths / sentinels. Everything else -- the non-streaming
# request/parse path, the end-of-stream success/failure reporting, and the
# PIPESTATUS epilogue -- was duplicated almost line-for-line. These helpers hold
# that shared logic, parameterised by the provider-specific bits, so a fix to
# any of it happens in one place.
#
# ell_curl / json_* / logging_* are provided by ell.sh (sourced before the
# backends), same as for the backends themselves.

# ell_backend_nonstreaming <url> <content_path> <finish_path> <stop_value> \
#                          <usage_key> <usage_prompt> <usage_completion> <usage_total>
# Run the non-streaming request: POST stdin to <url>, parse the response, and on
# a normal finish print the completion text (from <content_path>) followed by a
# blank line, logging usage if present. Prints nothing and returns non-zero on
# transport failure, parse failure, or an abnormal finish reason.
#
#   content_path   json path of the completion text (e.g. choices.0.message.content)
#   finish_path    json path of the finish reason  (e.g. choices.0.finish_reason)
#   stop_value     the finish reason meaning "ok"  (e.g. stop / STOP)
#   usage_key      json path that exists when usage is present (e.g. usage)
#   usage_*        json paths of the three usage counters
ell_backend_nonstreaming() {
  local url="${1}" content_path="${2}" finish_path="${3}" stop_value="${4}";
  local usage_key="${5}" usage_prompt="${6}" usage_completion="${7}" usage_total="${8}";
  local response curl_status prompt_tokens completion_tokens total_tokens;

  logging_debug "Streaming disabled";
  response=$(ell_curl "${url}" \
    --header "Content-Type: application/json" \
    --data-binary @-);
  curl_status="${?}";

  if [ "${curl_status}" -ne 0 ]; then
    logging_fatal "Failed to generate completion: $(ell_curl_strerror "${curl_status}") (curl exit ${curl_status})";
    logging_debug "Response: ${response}";
    return 1;
  fi

  if ! json_parse "${response}"; then
    logging_error "Unexpected format: ${response}";
    return 1;
  fi

  if ! json_has "${finish_path}"; then
    logging_error "Unexpected format: ${response}";
    return 1;
  fi

  if [ "x$(json_get "${finish_path}")" != "x${stop_value}" ]; then
    logging_error "Unexpected finish reason: $(json_get "${finish_path}")";
    return 1;
  fi

  json_get "${content_path}";
  echo "";
  if json_has "${usage_key}"; then
    prompt_tokens=$(json_get "${usage_prompt}");
    completion_tokens=$(json_get "${usage_completion}");
    total_tokens=$(json_get "${usage_total}");
    echo '';
    logging_info "usage: prompt_tokens=${prompt_tokens}, completion_tokens=${completion_tokens}, total_tokens=${total_tokens}";
  fi
}

# ell_backend_report_stream_end <emitted> <received> <unparsable> <bad_stop> <url>
# Emit the shared end-of-stream diagnostics and exit with the right code. Called
# from INSIDE the streaming reader subshell, so it uses `exit`, not `return`:
#   exit 3 - nothing usable was produced (empty / unparsable / no content)
#   exit 4 - a non-stop finish reason (truncated / filtered) was seen
# Returns 0 (does not exit) when content was emitted and the finish was normal.
ell_backend_report_stream_end() {
  local emitted="${1}" received="${2}" unparsable="${3}" bad_stop="${4}" url="${5}";
  if [ "${emitted}" -eq 0 ]; then
    if [ "${received}" -eq 0 ]; then
      logging_error "No data received from ${url} (empty or non-streaming response)";
    elif [ "${unparsable}" -ne 0 ]; then
      logging_error "Response could not be parsed as a valid streaming completion";
    else
      logging_error "Streaming response contained no content";
    fi
    exit 3;
  fi
  if [ "${bad_stop}" -ne 0 ]; then
    exit 4;
  fi
}

# ell_backend_check_pipestatus <curl_status> <stream_status>
# Shared PIPESTATUS epilogue for the streaming path. The caller must capture
# PIPESTATUS immediately after the `curl | { reader }` pipeline (any command
# resets it) and pass the two stages in. Preserves the distinct exit codes so a
# curl/transport failure is distinguishable from a stream-parse failure.
ell_backend_check_pipestatus() {
  local curl_status="${1}" stream_status="${2}";
  if [ "${curl_status}" -ne 0 ]; then
    logging_fatal "Failed to generate completion: $(ell_curl_strerror "${curl_status}") (curl exit ${curl_status})";
    return "${curl_status}";
  fi
  if [ "${stream_status}" -ne 0 ]; then
    return "${stream_status}";
  fi
  return 0;
}

export -f ell_backend_nonstreaming;
export -f ell_backend_report_stream_end;
export -f ell_backend_check_pipestatus;
