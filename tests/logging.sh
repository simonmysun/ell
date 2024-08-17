#!/usr/bin/env bash

export TO_TTY=true;

source $(dirname "$0")/../helpers/logging.sh;

export ELL_LOG_LEVEL=5;
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging::debug "logging::debug";
logging::warn "logging::warn";
logging::info "logging::info";
logging::error "logging::error";
logging::fatal "logging::fatal";

echo "ELL_LOG_LEVEL=3";
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging::debug "logging::debug";
logging::warn "logging::warn";
logging::info "logging::info";
logging::error "logging::error";
logging::fatal "logging::fatal";

echo "ELL_LOG_LEVEL=2";
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging::debug "logging::debug";
logging::warn "logging::warn";
logging::info "logging::info";
logging::error "logging::error";
logging::fatal "logging::fatal";

echo "ELL_LOG_LEVEL=0";
echo "ELL_LOG_LEVEL=${ELL_LOG_LEVEL}";

logging::debug "logging::debug";
logging::warn "logging::warn";
logging::info "logging::info";
logging::error "logging::error";
logging::fatal "logging::fatal";