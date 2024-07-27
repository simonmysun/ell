#!/usr/bin/env bash

ELL_VERSION="0.0.1";

: "${ELL_LOG_LEVEL:=3}";

BASE_DIR=$(dirname ${0});

source "${BASE_DIR}/helpers/logging.sh";

logging_debug "Starting ${0}";

logging_debug "END OF ELL";
