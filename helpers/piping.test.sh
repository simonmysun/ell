#!/usr/bin/env bash

# Self-checking tests for helpers/piping.sh.
#
# piping() joins an array of command strings into a single shell pipeline and
# runs it, feeding its own stdin to the first command. With no commands (or an
# empty first command) it must behave as a transparent pass-through (cat -).

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../tests/assert.sh";

# inc: increment every input digit modulo 10. Used to prove that data really
# flows through each stage of the pipeline in order.
inc() {
  while read -r -N 1 char; do
    printf '%s' $(( (char + 1) % 10 ));
  done
}
export -f inc;

. "${DIR}/piping.sh";

echo "piping tests";
echo "============";

# No commands: input passes through unchanged.
out="$(printf 'hello' | piping)";
assert_equals "no commands passes through" "hello" "${out}";

# Empty first command: also treated as pass-through.
out="$(printf 'hello' | piping '')";
assert_equals "empty command passes through" "hello" "${out}";

# Single command runs.
out="$(printf '000' | piping inc)";
assert_equals "single command applied once" "111" "${out}";

# Multiple commands chain in order: three inc stages turn 0 into 3.
out="$(printf '000' | piping inc inc inc)";
assert_equals "three stages chained" "333" "${out}";

# A real utility pipeline (not just inc) works too.
out="$(printf 'c\na\nb\n' | piping 'sort' 'tr a-z A-Z')";
assert_equals "sort then uppercase" "$(printf 'A\nB\nC')" "${out}";

# The original scenario: 256 zeros through 12 inc stages -> all '2', length 256.
out="$(head -c 256 < /dev/zero | tr '\0' '0' | piping inc inc inc inc inc inc inc inc inc inc inc inc)";
assert_equals "12 stages over 256 zeros" "$(head -c 256 < /dev/zero | tr '\0' '2')" "${out}";

assert_summary;
