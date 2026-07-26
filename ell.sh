#!/usr/bin/env bash

# ${BASH_VERSINFO:-0} is tested first because the BASH_VERSINFO array was introduced in bash-2.0-beta1. I have tested bash-2.05a.0(1)-release and the code below works.
if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
  if [ "${BASH_VERSINFO:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 1 ]; then
    echo "Bash version 4.1 or higher is required to run this script";
    exit 69;
  fi
else
  echo "Bash version 4.1 or higher is required to run this script";
  exit 69;
fi

ELL_VERSION="0.2.0";

: "${ELL_LOG_LEVEL:=2}";

# Resolve BASE_DIR to an absolute path. `dirname "${0}"` can be relative (e.g.
# "." when run as ./ell.sh); record mode re-execs ell via `script -c` in a
# shell that may have a different working directory, so a relative BASE_DIR
# would not resolve there. An absolute path is safe everywhere.
BASE_DIR=$(cd "$(dirname "${0}")" >/dev/null 2>&1 && pwd);
if [ -z "${BASE_DIR}" ]; then
  BASE_DIR=$(dirname "${0}");
fi

# logging_debug "Importing helper functions";
. "${BASE_DIR}/helpers/logging.sh";
. "${BASE_DIR}/helpers/parse_arguments.sh";
. "${BASE_DIR}/helpers/load_config.sh";
. "${BASE_DIR}/helpers/piping.sh";
. "${BASE_DIR}/helpers/json.sh";
. "${BASE_DIR}/helpers/resolve_paths.sh";
. "${BASE_DIR}/helpers/render_template.sh";
. "${BASE_DIR}/helpers/http.sh";
. "${BASE_DIR}/helpers/backend_common.sh";

logging_debug "Starting ${0}";

# logging_debug Loading configuration;
# This will load the configuration in order:
# 1. from configuration files
# 2. from default values in the script
# 3. from environment variables
# 4. from command line arguments

load_config;

: "${ELL_LLM_MODEL:=gpt-4o-mini}";
: "${ELL_LLM_TEMPERATURE:=0.6}";
: "${ELL_LLM_MAX_TOKENS:=4096}";
# ELL_TEMPLATE_PATH is intentionally left unset by default: templates are
# resolved through resolve_template() across the XDG and bundled search roots.
# Setting it explicitly (e.g. via -T) forces that single directory instead.
: "${ELL_TEMPLATE:=default-openai}";
: "${ELL_INPUT_FILE:=""}";
: "${ELL_RECORD:="false"}";
: "${ELL_INTERACTIVE:="false"}";
: "${ELL_OUTPUT_FILE:="-"}";
: "${ELL_API_STYLE:=openai}";
: "${ELL_API_KEY:=""}";
: "${ELL_API_URL:=""}";
: "${ELL_API_STREAM:="true"}";
: "${ELL_PS1:="$(printf "\e[0m\e[2m<\e[0muser_prompt\e[2m>\e[0m \e[34m\e[1m$\e[0m ")"}";
: "${ELL_PS2:="$(printf "\e[0m\e[2m<\e[0mllm_gen\e[2m>\e[0m ")"}";
: "${ELL_CONFIG:=""}";

parse_arguments "${@}";

. "${BASE_DIR}/llm_backends/generate_completion.sh";

# Preflight the essential API config so a first-run misconfiguration produces a
# clear, actionable message instead of an opaque curl error later. The ell_echo
# backend talks to no network, so it needs neither URL nor key.
if [ "x${ELL_API_STYLE}" != "xell_echo" ]; then
  if [ -z "${ELL_API_URL}" ]; then
    logging_fatal "ELL_API_URL is not set. Configure it (e.g. in \$XDG_CONFIG_HOME/ell/config or ~/.ellrc), pass --api-url, or set the ELL_API_URL environment variable. See docs/Configuration.md.";
    exit 78; # EX_CONFIG
  fi
  if [ -z "${ELL_API_KEY}" ]; then
    # An empty key is valid for some local/proxy endpoints, so warn rather than
    # fail; the request will still be attempted.
    logging_warn "ELL_API_KEY is not set; sending the request without an Authorization header. Set --api-key or ELL_API_KEY if your endpoint requires one.";
  fi
fi

# Deciding where to output. Redirect stdout to ELL_OUTPUT_FILE only when an
# output file other than "-" was requested AND we are not in record or
# interactive mode (in those modes stdout must stay on the terminal for the
# recorded/interactive session).
#
# The 'x' prefix must be on both sides of each comparison: ELL_RECORD and
# ELL_INTERACTIVE hold "true"/"false", never "xtrue", so the previous
# `"${ELL_RECORD}" != "xtrue"` was always true and the redirect fired even in
# record/interactive mode.
if [ "x${ELL_OUTPUT_FILE}" != "x-" ] \
   && [ "x${ELL_RECORD}" != "xtrue" ] \
   && [ "x${ELL_INTERACTIVE}" != "xtrue" ]; then
  logging_debug "Outputting to file: ${ELL_OUTPUT_FILE}";
  exec 1>"${ELL_OUTPUT_FILE}";
fi

# logging_debug "Checking if we are outputting to a TTY or not";
if [ -z "${TO_TTY}" ]; then
  [ -t 1 ] && TO_TTY=true || TO_TTY=false;
fi
export TO_TTY;
read -r PAGE_SIZE COLUMNS <<EOF
$(stty size)
EOF
if [ -z "${PAGE_SIZE}" ]; then
  PAGE_SIZE=24;
fi
if [ -z "${COLUMNS}" ]; then
  COLUMNS=80;
fi
export PAGE_SIZE;
export COLUMNS;

# Decorate generate_completion to apply the pre/post-LLM hooks around it: copy
# the backend's definition to orig_generate_completion, then redefine
# generate_completion as the wrapper below. `declare -f` prints just the
# function definition (no localizable "is a function" description line), so
# prefixing its output is cleaner and less fragile than splicing `command -V`.
eval "orig_$(declare -f generate_completion)";
generate_completion() {
  local pre_llm_hooks post_llm_hooks backend_status;
  # Use a here-string, not process substitution (`< <(...)`): the latter is a
  # parse error under `set -o posix` on bash 4.1, the oldest version ell
  # supports (see CONTRIBUTING.md). An empty result yields a single empty
  # element, which piping() treats as "no pipes" (its `[ "${1}" = '' ]` guard).
  mapfile -t pre_llm_hooks <<< "$(list_plugin_hooks _pre_llm.sh)";
  logging_debug "Pre LLM hooks: ${pre_llm_hooks[*]}";
  mapfile -t post_llm_hooks <<< "$(list_plugin_hooks _post_llm.sh)";
  logging_debug "Post LLM hooks: ${post_llm_hooks[*]}";
  piping "${pre_llm_hooks[@]}" \
  | orig_generate_completion \
  | piping "${post_llm_hooks[@]}";
  # Propagate the backend's status (the middle stage), not the last hook's, so
  # a failed completion is not masked by a successful post-LLM plugin.
  backend_status="${PIPESTATUS[1]}";
  return "${backend_status}";
}

# logging_debug "Checking if we are going to enter record mode";
# Enter record mode when we are recording OR interactive, AND the shell log is
# not "-" and does not already exist (i.e. we have not already re-exec'd under
# `script`). The (record OR interactive) part is grouped explicitly: `&&` and
# `||` share precedence and left-associate, so without the braces this reads as
# `((record || interactive) && ...)` -- correct today only by accident, and
# fragile to edit.
if { [ "x${ELL_RECORD}" = "xtrue" ] || [ "x${ELL_INTERACTIVE}" = "xtrue" ]; } \
   && [ "x${ELL_TMP_SHELL_LOG}" != "x-" ] \
   && [ ! -f "${ELL_TMP_SHELL_LOG}" ]; then
  if [ "x${ELL_OUTPUT_FILE}" != "x-" ]; then
    export ELL_TMP_SHELL_LOG="${ELL_OUTPUT_FILE}";
  else
    # Declare/assign separately so the assignment does not mask mktemp's status.
    ELL_TMP_SHELL_LOG="$(mktemp)";
    export ELL_TMP_SHELL_LOG;
  fi
  export ELL_RECORD=true;
  logging_info "Session being recorded to ${ELL_TMP_SHELL_LOG}";
  # The command to capture, as separate argv words. For an interactive session
  # re-exec this ell via its launcher by an absolute path rather than a bare
  # `ell`: relying on `ell` being on PATH breaks when ell is run in place (e.g.
  # ./ell.sh) or is not installed.
  if [ "x${ELL_INTERACTIVE}" = "xtrue" ]; then
    _ell_record_argv=("${BASE_DIR}/ell" -i);
  else
    _ell_record_argv=(bash -i);
  fi
  # GNU/util-linux and BSD/macOS `script` take incompatible command syntax:
  #   GNU:  script -q -c "CMD-STRING" LOGFILE      (command via $SHELL -c)
  #   BSD:  script -q LOGFILE CMD [args...]         (command as argv, execvp'd)
  # BSD script has neither -c nor -f (it errors "illegal option -- f"). Detect
  # the flavour once (side-effect-free; no PTY, cannot hang) and build the call
  # accordingly. On GNU, collapse the argv into one %q-quoted string for -c; on
  # BSD, pass the words positionally after the logfile.
  if script --version 2>/dev/null | grep -q util-linux; then
    printf -v _ell_record_cmd '%q ' "${_ell_record_argv[@]}";
    _ell_record_cmd="${_ell_record_cmd% }";
    script -q -c "${_ell_record_cmd}" "${ELL_TMP_SHELL_LOG}";
  else
    script -q "${ELL_TMP_SHELL_LOG}" "${_ell_record_argv[@]}";
  fi
  logging_debug "Removing ${ELL_TMP_SHELL_LOG}";
  if [ "x${ELL_OUTPUT_FILE}" = "x-" ]; then
    rm -f "${ELL_TMP_SHELL_LOG}";
  fi
  unset ELL_TMP_SHELL_LOG;
  unset ELL_RECORD;
  logging_info "Record mode exited";
  exit 0;
fi

# logging_debug "Resolving the template across the search roots";
ELL_TEMPLATE_FILE="$(resolve_template "${ELL_TEMPLATE}")";
if [ -z "${ELL_TEMPLATE_FILE}" ]; then
  if [ -n "${ELL_TEMPLATE_PATH}" ]; then
    logging_fatal "Template not found: ${ELL_TEMPLATE_PATH}${ELL_TEMPLATE}.json";
  else
    logging_fatal "Template not found: ${ELL_TEMPLATE}.json (searched XDG config/data, ~/.ellrc.d and ${BASE_DIR})";
  fi
  exit 1;
fi
logging_debug "Using template: ${ELL_TEMPLATE_FILE}";

# logging_debug "Checking if we are going to read from a file";
if [ -n "${ELL_INPUT_FILE}" ]; then
  if [ "x${ELL_INPUT_FILE}" != "x-" ] && [ ! -f "${ELL_INPUT_FILE}" ]; then
    logging_fatal "Input file not found: ${ELL_INPUT_FILE}";
    exit 1;
  else
    logging_debug "Reading input from file: ${ELL_INPUT_FILE}, overriding USER_PROMPT";
    # Read the file as raw text; JSON escaping is handled later by
    # render_template, and it is run through the post_input hooks below.
    USER_PROMPT="$(cat "${ELL_INPUT_FILE}")";
  fi
fi

# logging_debug "Loading the post_input and pre_output hooks";
# Here-string rather than process substitution: see the note in
# generate_completion() above (posix + bash 4.1 compatibility).
mapfile -t post_input_hooks <<< "$(list_plugin_hooks _post_input.sh)";
logging_debug "Post input hooks: ${post_input_hooks[*]}";
mapfile -t pre_output_hooks <<< "$(list_plugin_hooks _pre_output.sh)";
logging_debug "Pre output hooks: ${pre_output_hooks[*]}";

# logging_debug "Checking if we are using terminal output as context";
# The captured context is kept as raw text (JSON escaping is done later by
# render_template) and is run through the post_input hooks so that redaction and
# other input filters apply to the terminal context too, not just USER_PROMPT.
if [ -z "${ELL_TMP_SHELL_LOG}" ]; then
  logging_debug "ELL_TMP_SHELL_LOG not set";
else
  logging_debug "Loading shell log from ${ELL_TMP_SHELL_LOG}";
  SHELL_CONTEXT="$(tail -c 3000 "${ELL_TMP_SHELL_LOG}" | LC_ALL=C awk -f "${BASE_DIR}/helpers/render_to_text.awk" | piping "${post_input_hooks[@]}")";
fi

# logging_debug "Checking if we are going to enter interactive mode";
if [ "x${ELL_INTERACTIVE}" = "xtrue" ]; then
  # Debug/info-level hint only (kept quiet at the default log level). The loop
  # exits cleanly on Ctrl-D (EOF), so name that key rather than Ctrl-C.
  logging_info "Interactive mode enabled. Press Ctrl-D to exit";
  while true; do
    # ELL_PS1 already holds real escape bytes (built with printf when defaulted),
    # so print it verbatim. Use printf '%s' rather than `echo -ne`, whose -n/-e
    # handling varies across shells/echo implementations (and matches ELL_PS2).
    printf '%s' "${ELL_PS1}";
    # Capture read's status. On EOF (Ctrl-D) read returns non-zero; without
    # handling it the loop spun forever emitting empty completions. read may
    # still have stored a final unterminated line together with EOF, so process
    # that line if it is non-empty, then exit.
    IFS= read -r USER_PROMPT;
    read_status="${?}";
    if [ "${read_status}" -ne 0 ] && [ -z "${USER_PROMPT}" ]; then
      echo;
      logging_debug "EOF on input, exiting interactive mode";
      break;
    fi
    USER_PROMPT="$(echo "${USER_PROMPT}" | piping "${post_input_hooks[@]}")";
    logging_debug "Loading shell log from ${ELL_TMP_SHELL_LOG}";
    if [ -z "${ELL_TMP_SHELL_LOG}" ]; then
      logging_debug "ELL_TMP_SHELL_LOG not set";
    else
      # Raw text through the post_input hooks (redaction etc.); render_template
      # handles JSON escaping. Declare/assign separately (SC2155).
      SHELL_CONTEXT="$(tail -c 3000 "${ELL_TMP_SHELL_LOG}" | LC_ALL=C awk -f "${BASE_DIR}/helpers/render_to_text.awk" | piping "${post_input_hooks[@]}")";
      export SHELL_CONTEXT;
    fi
    PAYLOAD="$(render_template "${ELL_TEMPLATE_FILE}")";
    if [ -z "${PAYLOAD}" ]; then
      logging_error "Failed to build request payload from template ${ELL_TEMPLATE_FILE}";
      continue;
    fi
    printf "%s" "${ELL_PS2}";
    echo "${PAYLOAD}" | generate_completion | piping "${pre_output_hooks[@]}";
    completion_status="${PIPESTATUS[1]}";
    if [ "${completion_status}" -ne 0 ]; then
      logging_error "Completion failed (backend exited with ${completion_status})";
    fi
  done
  logging_debug "Exiting interactive mode";
else
  USER_PROMPT=$(echo "${USER_PROMPT}" | piping "${post_input_hooks[@]}");

  PAYLOAD="$(render_template "${ELL_TEMPLATE_FILE}")";
  if [ -z "${PAYLOAD}" ]; then
    logging_fatal "Failed to build request payload from template ${ELL_TEMPLATE_FILE}";
    exit 1;
  fi

  echo "${PAYLOAD}" | generate_completion | piping "${pre_output_hooks[@]}";
  completion_status="${PIPESTATUS[1]}";
  if [ "${completion_status}" -ne 0 ]; then
    logging_fatal "Completion failed (backend exited with ${completion_status})";
    exit "${completion_status}";
  fi
fi

logging_debug "END OF ELL";