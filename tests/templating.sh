#!/usr/bin/env bash

# Self-checking tests for template rendering.
#
# The ell_echo backend simply echoes the request body ell built, so pointing
# ell at it lets us inspect exactly what the templating step produced without
# any network. We assert that the chosen template shape is used, the model is
# substituted, the user prompt is embedded, and the result is valid JSON.

set -o posix;

DIR="$(cd "$(dirname "${0}")" && pwd)";
. "${DIR}/assert.sh";
. "${DIR}/../helpers/json.sh";

export ELL_TEMPLATE_PATH="${DIR}/../templates/";
export TO_TTY=false;

echo "templating tests";
echo "================";

# --- OpenAI template --------------------------------------------------------

out="$(printf '' | "${DIR}/../ell" --api-style ell_echo -m gpt-4o --api-disable-streaming UNIQUE_PROMPT_XYZ 2>/dev/null)";
assert_success  "openai template renders valid JSON" json_is_valid "${out}";
assert_contains "openai template uses messages array" "${out}" '"messages"';
assert_contains "openai template has role field"       "${out}" '"role"';
assert_contains "openai model substituted"             "${out}" '"gpt-4o"';
assert_contains "openai embeds user prompt"            "${out}" 'UNIQUE_PROMPT_XYZ';
assert_not_contains "openai not using gemini shape"    "${out}" '"contents"';

# --- Gemini template --------------------------------------------------------

# Disable streaming here too, matching the OpenAI case above, so both template
# checks run under one deterministic configuration. The gemini template does not
# currently reference ${ELL_API_STREAM}, so this does not change today's output;
# it keeps the two tests symmetric and guards the assertions if a "stream" field
# is ever added to default-gemini.json.
out="$(printf '' | "${DIR}/../ell" --api-style ell_echo -t default-gemini --api-disable-streaming UNIQUE_PROMPT_XYZ 2>/dev/null)";
assert_success  "gemini template renders valid JSON"  json_is_valid "${out}";
assert_contains "gemini template uses contents array" "${out}" '"contents"';
assert_contains "gemini template has parts field"      "${out}" '"parts"';
assert_contains "gemini embeds user prompt"            "${out}" 'UNIQUE_PROMPT_XYZ';
assert_not_contains "gemini not using openai shape"    "${out}" '"messages"';

assert_summary;
