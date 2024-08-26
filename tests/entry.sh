#!/usr/bin/env bash

set -o posix;

echo "Setting up prerequisites...";
apk -q add jq curl perl;

echo "Installing ell...";

echo -e '#!/usr/bin/env bash\n\n/ell/ell ${@}' > /usr/local/bin/ell;
chmod +x /usr/local/bin/ell;

cd "$(dirname "${0}")" || exit 1;

echo "Running tests...";

echo "Running test: logging.sh";
bash logging.sh;

echo "Running test: piping.sh";
bash piping.sh;

echo "Running test: templating.sh";
bash templating.sh;

echo "Running test: parse_input.sh";
bash parse_output.sh;