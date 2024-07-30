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
: "${ELL_INTERACTIVE:="false"}";
: "${ELL_API_STYLE:=openai}";
: "${ELL_API_KEY:=""}";
: "${ELL_API_URL:=""}";
: "${ELL_API_STREAM:="true"}";
: "${ELL_PS1:="<user_prompt> \$ "}";
: "${ELL_CONFIG:=""}";

[[ -t 1 ]] && TO_TTY=true || TO_TTY=false;
export TO_TTY;

BASE_DIR=$(dirname ${0});

source "${BASE_DIR}/helpers/logging.sh";
source "${BASE_DIR}/helpers/parse_arguments.sh";
source "${BASE_DIR}/helpers/load_config.sh";
source "${BASE_DIR}/helpers/piping.sh";
source "${BASE_DIR}/llm_backends/generate_completion.sh";

logging_debug "Starting ${0}";

load_config;
parse_arguments "${@}";

eval $(echo -ne "orig_"; declare -f generate_completion);
generate_completion() {
  pre_llm_hooks=$(ls ${BASE_DIR}/plugins/*/*_pre_llm.sh 2>/dev/null | sort -k3 -t/);
  logging_debug "Pre LLM hooks: ${pre_llm_hooks}";
  post_llm_hooks=$(ls ${BASE_DIR}/plugins/*/*_post_llm.sh 2>/dev/null | sort -k3 -t/);
  logging_debug "Post LLM hooks: ${post_llm_hooks}";
  piping "${pre_llm_hooks[@]}" \
  | orig_generate_completion \
  | piping "${post_llm_hooks[@]}";
}

if [[ "x${ELL_RECORD}" == "xtrue" && -z $ELL_TMP_SHELL_LOG ]]; then
  export ELL_TMP_SHELL_LOG=$(mktemp);
  export ELL_RECORD=true;
  logging_info "Session being recorded to ${ELL_TMP_SHELL_LOG}";
  if [[ "x${ELL_INTERACTIVE}" == "xtrue" ]]; then
    script -q -f -c "ell -i" ${ELL_TMP_SHELL_LOG};
  else
    script -q -f -c "bash -i" ${ELL_TMP_SHELL_LOG};
  fi
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

post_input_hooks=$(ls ${BASE_DIR}/plugins/*/*_post_input.sh 2>/dev/null | sort -k3 -t/);
logging_debug "Post input hooks: ${post_input_hooks}";
pre_output_hooks=$(ls ${BASE_DIR}/plugins/*/*_pre_output.sh 2>/dev/null | sort -k3 -t/);
logging_debug "Pre output hooks: ${pre_output_hooks}";

if [[ x${ELL_INTERACTIVE} == "xtrue" ]]; then
  logging_info "Interactive mode enabled. ^C to exit";
  while true; do
    IFS= read -e -p "$ELL_PS1" USER_PROMPT;
    USER_PROMPT=$(echo $USER_PROMPT | piping "${post_input_hooks[@]}");
    logging_debug "Loading shell log from ${ELL_TMP_SHELL_LOG}";
    if [[ -z "${ELL_TMP_SHELL_LOG}" ]]; then
      logging_debug "ELL_TMP_SHELL_LOG not set";
    else
      logging_debug "Loading shell log from ${ELL_TMP_SHELL_LOG}";
      SHELL_CONTEXT=$(tail -c 3000 ${ELL_TMP_SHELL_LOG} | ${BASE_DIR}/helpers/render_to_text.perl | sed  -e 's/\\/\\\\/g' -e 's/"/\\"/g'| awk '{printf "%s\\n", $0}');
    fi
    PAYLOAD=$(eval "cat <<EOF
$(<${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json)
EOF");

    echo $PAYLOAD | generate_completion | piping "${pre_output_hooks[@]}";
  done
  logging_debug "Exiting interactive mode";
else
  USER_PROMPT=$(echo $USER_PROMPT | piping "${post_input_hooks[@]}");

  PAYLOAD=$(eval "cat <<EOF
$(<${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json)
EOF");

  echo $PAYLOAD | generate_completion | piping "${pre_output_hooks[@]}";
fi

logging_debug "END OF ELL";