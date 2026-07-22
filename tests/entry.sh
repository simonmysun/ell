#!/usr/bin/env bash

set -o posix;

echo "Setting up prerequisites...";
apk -q add curl;

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

echo "Running test: parse_output.sh";
bash parse_output.sh;

echo "Running test: redaction.sh";
bash redaction.sh;

echo "Running test: render_to_text.sh";
bash render_to_text.sh;
render_to_text_status="${?}";

# render_to_text.sh is self-checking: propagate its result as the suite's exit
# status so a regression in the escape-sequence stripping fails CI.
exit "${render_to_text_status}";