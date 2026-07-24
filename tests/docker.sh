#!/usr/bin/env bash

# Run the test suite inside pinned bash containers (oldest and current
# supported). Uses `-i` without `-t`: allocating a TTY (`-t`) fails in
# non-interactive environments such as CI ("cannot attach stdin to a
# TTY-enabled container"), and the tests need no interactive terminal.
#
# The overall exit status is the OR of both runs, so a regression under either
# bash version fails the script (and therefore CI).

set -o posix;

cd "$(dirname "${0}")/.." || exit 1;

status=0;

for image in bash:4.1 bash:5.2; do
  echo "Running tests with ${image}";
  echo "===========================";
  if ! docker run -i --rm -v "${PWD}":/ell:ro "${image}" bash /ell/tests/entry.sh; then
    echo "Suite failed on ${image}";
    status=1;
  fi
done

exit "${status}";
