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
  echo "  -o, --output: output to file";
  echo "  --api-style: api style";
  echo "  --api-key: api key";
  echo "  --api-url: api url";
  echo "  --api-disable-streaming: disable api response streaming";
  echo "  -c, --config: config file";
  echo "  -l, --log-level: log level";
  echo "  -O, --option: other options, e.g. -o A=b -o C=d,E=f";
  echo "  PROMPT: prompt to input";
  echo "For more information, see https://github.com/simonmysun/ell";
}

print_version() {
  echo "${0} $ELL_VERSION https://github.com/simonmysun/ell";
}

parse_arguments() {
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
        logging_debug "\"-l\" present in args, setting ELL_LOG_LEVEL to ${2}";
        export ELL_LOG_LEVEL="${2}";
        shift 2;
        ;;
      -m|--model)
        logging_debug "\"-m\" present in args, setting ELL_LLM_MODEL to ${2}";
        export ELL_LLM_MODEL="${2}";
        shift 2;
        ;;
      -T|--template-path)
        logging_debug "\"-T\" present in args, setting ELL_TEMPLATE_PATH to ${2}";
        export ELL_TEMPLATE_PATH="${2}";
        shift 2;
        ;;
      -t|--template)
        logging_debug "\"-t\" present in args, setting ELL_TEMPLATE to ${2}";
        export ELL_TEMPLATE="${2}";
        shift 2;
        ;;
      -f|--input-file)
        logging_debug "\"-f\" present in args, setting ELL_INPUT_FILE to ${2}";
        export ELL_INPUT_FILE="${2}";
        shift 2;
        ;;
      -r|--record)
        logging_debug "\"-r\" present in args, setting ELL_RECORD to true";
        if [ "${ELL_RECORD}" = "xtrue" ]; then
          logging_fatal "Record mode already enabled";
          exit 1;
        fi
        ELL_RECORD=true;
        shift 1;
        ;;
      -o|--output-file)
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
        logging_debug "\"--api-style\" present in args, setting ELL_API_STYLE to ${2}";
        export ELL_API_STYLE="${2}";
        shift 2;
        ;;
      --api-key)
        logging_debug "\"--api-key\" present in args, setting ELL_API_KEY to ${2}";
        export ELL_API_KEY="${2}";
        shift 2;
        ;;
      --api-url)
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
        logging_debug "\"-c\" present in args, setting ELL_CONFIG to ${2}";
        export ELL_CONFIG="${2}";
        shift 2;
        ;;
      -O|--option)
        # -o A=b -o C=d,E=f
        logging_debug "\"-o\" present in args";
        other_options="${2}";
        other_options_array=();
        IFS=',' read -r -a other_options_array <<EOF
${other_options}
EOF
        echo "${other_options_array[@]}";
        for option in "${other_options_array[@]}"; do
          IFS='=' read -r -a option_array <<EOF
${option}
EOF
          key="${option_array[0]}";
          value="${option_array[1]}";
          logging_debug "Setting ${key} to ${value}";
          eval "export ${key}=${value}";
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