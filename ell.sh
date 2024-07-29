#!/usr/bin/env bash

ELL_VERSION="0.0.1";

: "${ELL_LOG_LEVEL:=3}";
: "${ELL_LLM_MODEL:=gpt-4o-mini}";
: "${ELL_LLM_TEMPERATURE:=0.6}";
: "${ELL_LLM_MAX_TOKENS:=4096}";
: "${ELL_TEMPLATE_PATH:=~/.ellrc.d/templates}";
: "${ELL_TEMPLATE:=default}";
: "${ELL_INPUT_FILE:=""}";
: "${ELL_RECORD:="false"}";
: "${ELL_API_STYLE:=openai}";
: "${ELL_API_KEY:=""}";
: "${ELL_API_URL:=""}";
: "${ELL_API_STREAM:="true"}";
: "${ELL_CONFIG:=""}";

BASE_DIR=$(dirname ${0});

source "${BASE_DIR}/helpers/logging.sh";
source "${BASE_DIR}/helpers/parse_arguments.sh";
source "${BASE_DIR}/helpers/load_config.sh";
source "${BASE_DIR}/llm_backends/generate_completion.sh";

logging_debug "Starting ${0}";

load_config;
parse_arguments "${@}";

if [[ "x${ELL_RECORD}" == "xtrue" && -z $ELL_TMP_SHELL_LOG ]]; then
  export ELL_TMP_SHELL_LOG=$(mktemp);
  export ELL_RECORD=true;
  logging_info "Session being recorded to ${ELL_TMP_SHELL_LOG}";
  script -q -f -c "bash -i" ${ELL_TMP_SHELL_LOG};
  logging_debug "Removing ${ELL_TMP_SHELL_LOG}";
  rm -f ${ELL_TMP_SHELL_LOG};
  unset ELL_TMP_SHELL_LOG;
  unset ELL_RECORD;
  logging_info "Record mode exited";
  exit 0;
fi

if [[ ! -f "${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json" ]]; then
  logging_fatal "Template not found: ${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json";
  exit 1;
fi

if [[ ! -z "${ELL_INPUT_FILE}" ]]; then
  if [[ ! -f "${ELL_INPUT_FILE}" ]]; then
    logging_fatal "Input file not found: ${ELL_INPUT_FILE}";
    exit 1;
  else
    logging_debug "Reading input from file: ${ELL_INPUT_FILE}, overriding USER_PROMPT";
    USER_PROMPT=$(cat ${ELL_INPUT_FILE} | sed  -e 's/\\/\\\\/g' -e 's/"/\\"/g'| awk '{printf "%s\\n", $0}');
  fi
fi

if [[ -z "${ELL_TMP_SHELL_LOG}" ]]; then
  logging_debug "ELL_TMP_SHELL_LOG not set";
else
  logging_debug "Loading shell log from ${ELL_TMP_SHELL_LOG}";
  SHELL_CONTEXT=$(tail -c 3000 ${ELL_TMP_SHELL_LOG} | ${BASE_DIR}/helpers/render_to_text.perl | sed  -e 's/\\/\\\\/g' -e 's/"/\\"/g'| awk '{printf "%s\\n", $0}');
fi

  PAYLOAD=$(eval "cat <<EOF
$(<${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json)
EOF
");

  logging_debug "PAYLOAD: ${PAYLOAD}";

  generate_completion "${PAYLOAD}";

logging_debug "END OF ELL";
