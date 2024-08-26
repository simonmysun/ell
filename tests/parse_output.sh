#!/usr/bin/env bash

set -o posix;

echo "";
echo "gemini stream mode to tty";
echo "=========================";
export ELL_API_STYLE=gemini;
export ELL_LLM_MODEL=gemini-1.5-flash;
export ELL_API_STREAM=true;
export ELL_API_URL="file://${PWD}/${ELL_API_STYLE}-$([ "x${ELL_API_STREAM}" == "xtrue" ] && echo "" || echo "no-")stream.json#";
export ELL_API_KEY="";
export ELL_TEMPLATE_PATH="${PWD}/../templates/";
export ELL_TEMPLATE="default-${ELL_API_STYLE}";
ell test;

echo "";
echo "gemini no-stream mode to tty";
echo "============================";
export ELL_API_STREAM=false;
export ELL_API_URL="file://${PWD}/${ELL_API_STYLE}-$([ "x${ELL_API_STREAM}" == "xtrue" ] && echo "" || echo "no-")stream.json#";
ell test;

export TO_TTY=false;

echo "";
echo "openai stream mode to file";
echo "==========================";
export ELL_API_STYLE=openai;
export ELL_LLM_MODEL=gpt-4o-mini;
export ELL_API_STREAM=true;
export ELL_API_URL="file://${PWD}/${ELL_API_STYLE}-$([ "x${ELL_API_STREAM}" == "xtrue" ] && echo "" || echo "no-")stream.json#";
export ELL_API_KEY="";
export ELL_TEMPLATE_PATH="${PWD}/../templates/";
export ELL_TEMPLATE="default-${ELL_API_STYLE}";
ell test;

echo "";
echo "openai no-stream mode to file";
echo "=============================";
export ELL_API_STREAM=false;
export ELL_API_URL="file://${PWD}/${ELL_API_STYLE}-$([ "x${ELL_API_STREAM}" == "xtrue" ] && echo "" || echo "no-")stream.json#";
ell test;