#!/usr/bin/env bash

# End-to-end tests for ell.sh's plugin hook integration.
#
# ell defines four hook points and applies them at specific stages of the
# pipeline:
#   post_input  - transforms USER_PROMPT before it is put into the template
#   pre_llm     - transforms the request payload before it reaches the backend
#   post_llm    - transforms the backend's response
#   pre_output  - transforms the final text before it is written to stdout
#
# The individual pieces (piping, hook discovery, the bundled hook scripts) have
# unit tests, but ell.sh's orchestration -- discovering hooks and applying each
# at the correct stage -- was only covered indirectly. These tests install a
# custom plugin with all four hooks, each leaving a distinct marker, and use the
# ell_echo backend (which echoes the request payload) to prove each hook ran at
# the right point in the data flow.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;

# Isolated search roots so only our probe plugin (and the bundled ones, which
# are TTY-gated and pass through under TO_TTY=false) are discovered.
CFG="${WORK}/cfg";
PLUGIN="${CFG}/ell/plugins/probe";
mkdir -p "${PLUGIN}" "${WORK}/data" "${WORK}/home";

# post_input: append _POSTINPUT to the prompt (before templating).
printf '#!/usr/bin/env bash\nsed '\''s/$/_POSTINPUT/'\''\n' > "${PLUGIN}/10_post_input.sh";
# pre_llm: prefix the payload's first line (before it reaches the backend).
printf '#!/usr/bin/env bash\nsed '\''1s/^/PRELLM_/'\''\n' > "${PLUGIN}/10_pre_llm.sh";
# post_llm: append _POSTLLM to every line of the backend response.
printf '#!/usr/bin/env bash\nsed '\''s/$/_POSTLLM/'\''\n' > "${PLUGIN}/10_post_llm.sh";
# pre_output: append _PREOUTPUT to every line of the final output.
printf '#!/usr/bin/env bash\nsed '\''s/$/_PREOUTPUT/'\''\n' > "${PLUGIN}/10_pre_output.sh";
chmod +x "${PLUGIN}"/*.sh;

run() {
  printf '' | env \
    XDG_CONFIG_HOME="${CFG}" XDG_DATA_HOME="${WORK}/data" HOME="${WORK}/home" \
    ELL_TEMPLATE_PATH="${DIR}/../templates/" TO_TTY=false \
    "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming "HELLO" \
    2>/dev/null;
}

echo "hook integration tests";
echo "======================";

out="$(run)";

# post_input ran before templating: the transformed prompt is embedded in the
# payload's user content.
assert_contains "post_input transforms the prompt before templating" \
  "${out}" "HELLO_POSTINPUT";

# pre_llm ran before the backend: its prefix is on the payload the backend
# echoed back (the payload starts with the JSON object, so PRELLM_ precedes '{').
assert_contains "pre_llm transforms the payload before the backend" \
  "${out}" "PRELLM_{";

# post_llm ran on the backend response, and pre_output ran after post_llm: every
# line ends with _POSTLLM_PREOUTPUT (post_llm applied first, then pre_output).
assert_contains "post_llm then pre_output applied in order" \
  "${out}" "_POSTLLM_PREOUTPUT";

# All four hook markers are present.
for marker in _POSTINPUT PRELLM_ _POSTLLM _PREOUTPUT; do
  assert_contains "hook marker ${marker} present" "${out}" "${marker}";
done

# With no custom plugins installed, output is unaffected by these markers
# (guards against the markers leaking from somewhere else).
plain="$(
  printf '' | env \
    XDG_CONFIG_HOME="${WORK}/empty" XDG_DATA_HOME="${WORK}/empty" HOME="${WORK}/empty" \
    ELL_TEMPLATE_PATH="${DIR}/../templates/" TO_TTY=false \
    "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming "HELLO" \
    2>/dev/null;
)";
assert_not_contains "no probe markers without the plugin" "${plain}" "_POSTLLM";

assert_summary;
