#!/usr/bin/env bash

set -o posix;

export ELL_TEMPLATE_PATH='/ell/templates/';

echo "openai template test";
ell --api-style ell_echo -m gpt-4o --api-stream false test;

echo "gemini template test";
ell --api-style ell_echo -t default-gemini test;
