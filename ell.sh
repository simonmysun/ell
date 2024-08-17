#!/usr/bin/env bash

# ${BASH_VERSINFO:-0} is tested first because the BASH_VERSINFO array was introduced in bash-2.0-beta1. I have tested bash-2.05a.0(1)-release and the code below works.
if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
  if [ "${BASH_VERSINFO:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; then
    echo "Bash version 4.2 or higher is required to run this script";
    exit 69;
  fi
else
  echo "Bash version 4.2 or higher is required to run this script";
  exit 69;
fi

ELL_VERSION="0.1.0";

BASE_DIR=$(dirname ${0});

# logging_debug "Importing helper functions";
source "${BASE_DIR}/helpers/logging.sh";
source "${BASE_DIR}/helpers/parse_arguments.sh";
source "${BASE_DIR}/helpers/load_config.sh";
source "${BASE_DIR}/helpers/piping.sh";

logging_debug "Starting ${0}";

# logging_debug Loading configuration;
# This will load the configuration in order:
# 1. from configuration files
# 2. from default values in the script
# 3. from environment variables
# 4. from command line arguments

load_config;

: "${ELL_LOG_LEVEL:=2}";
: "${ELL_LLM_MODEL:=gpt-4o-mini}";
: "${ELL_LLM_TEMPERATURE:=0.6}";
: "${ELL_LLM_MAX_TOKENS:=4096}";
: "${ELL_TEMPLATE_PATH:="${HOME}/.ellrc.d/templates/"}";
: "${ELL_TEMPLATE:=default-openai}";
: "${ELL_INPUT_FILE:=""}";
: "${ELL_RECORD:="false"}";
: "${ELL_INTERACTIVE:="false"}";
: "${ELL_OUTPUT_FILE:="-"}";
: "${ELL_API_STYLE:=openai}";
: "${ELL_API_KEY:=""}";
: "${ELL_API_URL:=""}";
: "${ELL_API_STREAM:="true"}";
: "${ELL_PS1:="$(tput sgr0; tput dim)<$(tput sgr0)user_prompt$(tput dim)>$(tput sgr0) $(tput setaf 4; tput bold)\$$(tput sgr0) "}";
: "${ELL_PS2:="$(tput sgr0; tput dim)<$(tput sgr0)llm_gen$(tput dim)>$(tput sgr0) "}";
: "${ELL_CONFIG:=""}";

parse_arguments "${@}";

source "${BASE_DIR}/llm_backends/generate_completion.sh";

# Deciding where to output
if [[ ${ELL_OUTPUT_FILE} != "-" ]]; then
  if [[ ${ELL_RECORD} != true && ${ELL_INTERACTIVE} != true ]]; then
    logging_debug "Outputting to file: ${ELL_OUTPUT_FILE}";
    exec 1>${ELL_OUTPUT_FILE};
  fi
fi

# logging_debug "Checking if we are outputting to a TTY or not";
if [[ -z "${TO_TTY}" ]]; then
  [[ -t 1 ]] && TO_TTY=true || TO_TTY=false;
fi
export TO_TTY;

# Logging_debug "Decorating the generate_completion to apply hooks before and after";
eval "$(echo -ne "orig_"; declare -f generate_completion)";
generate_completion() {
  pre_llm_hooks=$(ls ${BASE_DIR}/plugins/*/*_pre_llm.sh 2>/dev/null | sort -k3 -t/);
  logging_debug "Pre LLM hooks: ${pre_llm_hooks}";
  post_llm_hooks=$(ls ${BASE_DIR}/plugins/*/*_post_llm.sh 2>/dev/null | sort -k3 -t/);
  logging_debug "Post LLM hooks: ${post_llm_hooks}";
  piping "${pre_llm_hooks[@]}" \
  | orig_generate_completion \
  | piping "${post_llm_hooks[@]}";
}

# Logging_debug "Checking if we are going to enter record mode";
if [[ ${ELL_RECORD} == true || ${ELL_INTERACTIVE} == true ]] && [[ "x${ELL_TMP_SHELL_LOG}" != "x-" && ! -f "${ELL_TMP_SHELL_LOG}" ]]; then
  if [[ "x${ELL_OUTPUT_FILE}" != "x-" ]]; then
    export ELL_TMP_SHELL_LOG=${ELL_OUTPUT_FILE}
  else
    export ELL_TMP_SHELL_LOG=$(mktemp);
  fi
  export ELL_RECORD=true;
  logging_info "Session being recorded to ${ELL_TMP_SHELL_LOG}";
  if [[ ${ELL_INTERACTIVE} == true ]]; then
    script -q -f -c "ell -i" "${ELL_TMP_SHELL_LOG}";
  else
    script -q -f -c "bash -i" "${ELL_TMP_SHELL_LOG}";
  fi
  logging_debug "Removing ${ELL_TMP_SHELL_LOG}";
  if [[ ${ELL_OUTPUT_FILE} == "-" ]]; then
    rm -f "${ELL_TMP_SHELL_LOG}";
  fi
  unset ELL_TMP_SHELL_LOG;
  unset ELL_RECORD;
  logging_info "Record mode exited";
  exit 0;
fi

# Logging_debug "Checking if the template is available";
if [[ ! -f "${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json" ]]; then
  logging_fatal "Template not found: ${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json";
  exit 1;
fi

# Logging_debug "Checking if we are going to read from a file";
if [[ ! -z "${ELL_INPUT_FILE}" ]]; then
  if [[ "x${ELL_INPUT_FILE}" != "x-" && ! -f "${ELL_INPUT_FILE}" ]]; then
    logging_fatal "Input file not found: ${ELL_INPUT_FILE}";
    exit 1;
  else
    logging_debug "Reading input from file: ${ELL_INPUT_FILE}, overriding USER_PROMPT";
    USER_PROMPT=$(cat ${ELL_INPUT_FILE} | sed  -e 's/\\/\\\\/g' -e 's/"/\\"/g'| awk '{printf "%s\\n", $0}');
  fi
fi

# Logging_debug "Checking if we are using terminal output as context";
if [[ -z "${ELL_TMP_SHELL_LOG}" ]]; then
  logging_debug "ELL_TMP_SHELL_LOG not set";
else
  logging_debug "Loading shell log from ${ELL_TMP_SHELL_LOG}";
  SHELL_CONTEXT="$(tail -c 3000 "${ELL_TMP_SHELL_LOG}" | ${BASE_DIR}/helpers/render_to_text.perl | sed  -e 's/\\/\\\\/g' -e 's/"/\\"/g'| awk '{printf "%s\\n", $0}')";
fi

# Logging_debug "Loading the post_input and pre_output hooks";
post_input_hooks=$(ls ${BASE_DIR}/plugins/*/*_post_input.sh 2>/dev/null | sort -k3 -t/);
logging_debug "Post input hooks: ${post_input_hooks}";
pre_output_hooks=$(ls ${BASE_DIR}/plugins/*/*_pre_output.sh 2>/dev/null | sort -k3 -t/);
logging_debug "Pre output hooks: ${pre_output_hooks}";

# Logging_debug "Checking if we are going to enter interactive mode";
if [[ ${ELL_INTERACTIVE} == true ]]; then
  logging_info "Interactive mode enabled. ^C to exit";
  while true; do
    echo -ne "${ELL_PS1}";
    IFS= read -r USER_PROMPT;
    USER_PROMPT="$(echo "${USER_PROMPT}" | piping "${post_input_hooks[@]}")";
    logging_debug "Loading shell log from ${ELL_TMP_SHELL_LOG}";
    if [[ -z "${ELL_TMP_SHELL_LOG}" ]]; then
      logging_debug "ELL_TMP_SHELL_LOG not set";
    else
      SHELL_CONTEXT="$(tail -c 3000 "${ELL_TMP_SHELL_LOG}" | ${BASE_DIR}/helpers/render_to_text.perl | sed  -e 's/\\/\\\\/g' -e 's/"/\\"/g'| awk '{printf "%s\\n", $0}')";
    fi
    PAYLOAD="$(eval "cat <<EOF
$(<${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json)
EOF")";
    echo -ne "${ELL_PS2}";
    echo "${PAYLOAD}" | generate_completion | piping "${pre_output_hooks[@]}";
  done
  logging_debug "Exiting interactive mode";
else
  USER_PROMPT=$(echo "${USER_PROMPT}" | piping "${post_input_hooks[@]}");

  PAYLOAD="$(eval "cat <<EOF
$(<${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json)
EOF")";

  echo "${PAYLOAD}" | generate_completion | piping "${pre_output_hooks[@]}";
fi

logging_debug "END OF ELL";