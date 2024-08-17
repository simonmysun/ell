#!/usr/bin/env bash

apk add jq curl perl;

cd $(dirname "$0");

echo "Running tests...";

echo "Running test: parse_input.sh";
bash parse_output.sh;