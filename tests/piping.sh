#!/usr/bin/env bash

set -o posix;

function inc() {
  while read -r -N 1 char; do
    echo -ne $(( (char + 1) % 10 ));
  done
}

export -f inc;

. "$(dirname "${0}")/../helpers/piping.sh";

head -c 256 < /dev/zero | tr '\0' '0' | piping inc inc inc inc inc inc inc inc inc inc inc inc;

echo "";