#!/usr/bin/env bash

set -o posix;

inc() {
  while read -r -N 1 char; do
    printf '%s' $(( (char + 1) % 10 ));
  done
}

export -f inc; # why -f is necessary?

. "$(dirname "${0}")/../helpers/piping.sh";

head -c 256 < /dev/zero | tr '\0' '0' | piping inc inc inc inc inc inc inc inc inc inc inc inc;

echo "";