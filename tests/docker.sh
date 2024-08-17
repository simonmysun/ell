#!/usr/bin/env bash

cd ..;

echo "Running tests with bash:4.1";
echo "===========================";
docker run -it --rm -v .:/ell:ro bash:4.1 bash /ell/tests/entry.sh;

echo "Running tests with bash:5.2";
echo "===========================";
docker run -it --rm -v .:/ell:ro bash:5.2 bash /ell/tests/entry.sh;