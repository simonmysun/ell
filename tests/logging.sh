#!/usr/bin/env bash

set -o posix;

export TO_TTY=true;

source "$(dirname "${0}")/../helpers/logging.sh";

export ELL_LOG_LEVEL=5;
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging_debug "logging_debug";
logging_warn "logging_warn";
logging_info "logging_info";
logging_error "logging_error";
logging_fatal "logging_fatal";

export ELL_LOG_LEVEL=3;
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging_debug "logging_debug";
logging_warn "logging_warn";
logging_info "logging_info";
logging_error "logging_error";
logging_fatal "logging_fatal";

export ELL_LOG_LEVEL=2;
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging_debug "logging_debug";
logging_warn "logging_warn";
logging_info "logging_info";
logging_error "logging_error";
logging_fatal "logging_fatal";

export ELL_LOG_LEVEL=0;
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging_debug "logging_debug";
logging_warn "logging_warn";
logging_info "logging_info";
logging_error "logging_error";
logging_fatal "logging_fatal";