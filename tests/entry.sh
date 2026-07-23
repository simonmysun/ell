#!/usr/bin/env bash

set -o posix;

echo "Setting up prerequisites...";
apk -q add curl;

echo "Installing ell...";

echo -e '#!/usr/bin/env bash\n\n/ell/ell ${@}' > /usr/local/bin/ell;
chmod +x /usr/local/bin/ell;

cd "$(dirname "${0}")" || exit 1;

echo "Running tests...";

# Track the overall suite status. Any test that exits non-zero must fail CI,
# so we remember the first failure instead of letting a later passing test
# mask an earlier regression.
suite_status=0;

run_test() {
  echo "Running test: ${1}";
  bash "${1}";
  status="${?}";
  if [ "${status}" -ne 0 ]; then
    echo "Test failed: ${1} (exit ${status})";
    suite_status=1;
  fi;
}

run_test logging.sh;
run_test piping.sh;
run_test templating.sh;
run_test parse_output.sh;
run_test redaction.sh;
run_test render_to_text.sh;

# Propagate the suite status: fail if any test above failed, so a regression in
# any test (not just render_to_text.sh's escape-sequence stripping) fails CI.
exit "${suite_status}";