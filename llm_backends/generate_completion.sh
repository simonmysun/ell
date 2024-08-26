#!/usr/bin/env bash

# Sourcing the generate_completion.sh script according to the selected API style
. "$(dirname ${0})/llm_backends/${ELL_API_STYLE}/generate_completion.sh";