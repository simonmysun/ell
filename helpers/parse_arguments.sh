#!/usr/bin/env bash

print_usage() {
  echo "Usage: ${0} [options] PROMPT";
  echo "  -h, --help: show this help";
  echo "  -V, --version: show version";
  echo "  -m, --model: model name";
  echo "  -T, --template-path: path to search for templates";
  echo "  -t, --template: template filename without extension";
  echo "  -f, --input-file: use file as input prompt, use - for stdin";
  echo "  -r, --record: enter record mode";
  echo "  -i, --interactive: enter interactive mode";
  echo "  -o, --output, --output-file: output to file";
  echo "  --api-style: api style";
  echo "  --api-key: api key (NOT recommended in multi-user environment)";
  echo "  --api-url: api url";
  echo "  --api-disable-streaming: disable api response streaming";
  echo "  -c, --config: config file";
  echo "  -l, --log-level: log level";
  echo "  -O, --option: other options, e.g. -O A=b -O C=d,E=f";
  echo "  PROMPT: prompt to input";
  echo "For more information, see https://github.com/simonmysun/ell";
}

print_version() {
  echo "${0} $ELL_VERSION https://github.com/simonmysun/ell";
}

# _require_arg <count> <flag>: fail with a usage error unless at least <count>
# arguments remain (i.e. the flag <flag> was actually given its value). Without
# this, a trailing option like `ell -m` leaves only one argument, `shift 2`
# fails, and the while loop spins forever on the same argument.
_require_arg() {
  if [ "${1}" -lt 2 ]; then
    logging_fatal "Option ${2} requires an argument";
    exit 64; # EX_USAGE
  fi
}

parse_arguments() {
  local other_options other_options_array option option_array key value;
  if [ ${#} -eq 0 ]; then
    if [ "x${ELL_RECORD}" = "xtrue" ]; then
      logging_debug "Record mode enabled. Context is used.";
    else
      logging_debug "No arguments provided, printing usage";
      print_usage;
      exit 64; # EX_USAGE
    fi
  fi
  while [ ${#} -gt 0 ]; do
    case "${1}" in
      -h|--help)
        logging_debug "\"-h\" present in args, printing usage";
        print_usage;
        exit 0;
        ;;
      -V|--version)
        logging_debug "\"-V\" present in args, printing version";
        print_version;
        exit 0;
        ;;
      -l|--log-level)
        _require_arg ${#} "-l/--log-level";
        logging_debug "\"-l\" present in args, setting ELL_LOG_LEVEL to ${2}";
        export ELL_LOG_LEVEL="${2}";
        shift 2;
        ;;
      -m|--model)
        _require_arg ${#} "-m/--model";
        logging_debug "\"-m\" present in args, setting ELL_LLM_MODEL to ${2}";
        export ELL_LLM_MODEL="${2}";
        shift 2;
        ;;
      -T|--template-path)
        _require_arg ${#} "-T/--template-path";
        logging_debug "\"-T\" present in args, setting ELL_TEMPLATE_PATH to ${2}";
        export ELL_TEMPLATE_PATH="${2}";
        shift 2;
        ;;
      -t|--template)
        _require_arg ${#} "-t/--template";
        logging_debug "\"-t\" present in args, setting ELL_TEMPLATE to ${2}";
        export ELL_TEMPLATE="${2}";
        shift 2;
        ;;
      -f|--input-file)
        _require_arg ${#} "-f/--input-file";
        logging_debug "\"-f\" present in args, setting ELL_INPUT_FILE to ${2}";
        export ELL_INPUT_FILE="${2}";
        shift 2;
        ;;
      -r|--record)
        logging_debug "\"-r\" present in args, setting ELL_RECORD to true";
        # The 'x' prefix must be on both sides: ELL_RECORD holds "true"/"false",
        # never "xtrue", so `"${ELL_RECORD}" = "xtrue"` never matched and this
        # "already enabled" guard was dead code.
        if [ "x${ELL_RECORD}" = "xtrue" ]; then
          logging_fatal "Record mode already enabled";
          exit 1;
        fi
        # export for consistency with the other flags (e.g. -i), so record mode
        # is visible to child processes (notably the script-spawned session).
        export ELL_RECORD=true;
        shift 1;
        ;;
      -o|--output|--output-file)
        _require_arg ${#} "-o/--output";
        logging_debug "\"-o\" present in args, setting ELL_OUTPUT_FILE to ${2}";
        export ELL_OUTPUT_FILE="${2}";
        shift 2;
        ;;
      -i|--interactive)
        logging_debug "\"-i\" present in args, setting ELL_INTERACTIVE to true";
        export ELL_INTERACTIVE=true;
        shift 1;
        ;;
      --api-style)
        _require_arg ${#} "--api-style";
        logging_debug "\"--api-style\" present in args, setting ELL_API_STYLE to ${2}";
        export ELL_API_STYLE="${2}";
        shift 2;
        ;;
      --api-key)
        _require_arg ${#} "--api-key";
        # Never log the key value, even at debug level: it is a secret and the
        # log may be shared or captured. Log only that it was set.
        logging_debug "\"--api-key\" present in args, setting ELL_API_KEY (value redacted)";
        export ELL_API_KEY="${2}";
        shift 2;
        ;;
      --api-url)
        _require_arg ${#} "--api-url";
        logging_debug "\"--api-url\" present in args, setting ELL_API_URL to ${2}";
        export ELL_API_URL="${2}";
        shift 2;
        ;;
      --api-disable-streaming)
        logging_debug "\"--api-disable-streaming\" present in args, setting ELL_API_STREAM to false";
        export ELL_API_STREAM="false";
        shift 1;
        ;;
      -c|--config)
        _require_arg ${#} "-c/--config";
        logging_debug "\"-c\" present in args, setting ELL_CONFIG to ${2}";
        export ELL_CONFIG="${2}";
        shift 2;
        ;;
      -O|--option)
        _require_arg ${#} "-O/--option";
        # -O A=b -O C=d,E=f
        logging_debug "\"-O\" present in args";
        other_options="${2}";
        other_options_array=();
        IFS=',' read -r -a other_options_array <<EOF
${other_options}
EOF
        for option in "${other_options_array[@]}"; do
          # Split only on the first "=", so values may themselves contain "=".
          key="${option%%=*}";
          value="${option#*=}";
          # Reject anything that is not a valid shell variable name so the
          # value below can never be interpreted as code (e.g. "X=$(rm -rf ~)").
          if [ "x${key}" = "x${option}" ]; then
            logging_error "Ignoring malformed -O option (expected KEY=VALUE): ${option}";
            continue;
          fi
          if ! [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            logging_error "Ignoring -O option with invalid variable name: ${key}";
            continue;
          fi
          logging_debug "Setting ${key} to ${value}";
          export "${key}=${value}";
        done
        shift 2;
        ;;
      *)
        logging_debug "No more options, setting prompt to ${*}";
        export USER_PROMPT="${*}";
        break;
        ;;
    esac
  done
}