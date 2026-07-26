# Backends

A backend adapts ell to one LLM HTTP API "style". The backend to use is
selected by `ELL_API_STYLE` (or `--api-style`), defaulting to `openai`.

## Built-in backends

| `ELL_API_STYLE` | API | Notes |
|-----------------|-----|-------|
| `openai`  | OpenAI-compatible chat completions | default; use `default-openai` template |
| `gemini`  | Google Gemini (v1beta)             | use `default-gemini` template |
| `ell_echo`| none — echoes the request body     | for debugging/testing; no network |

The `ell_echo` backend simply writes the request payload it received to stdout,
which makes it handy for inspecting exactly what a template produced.

## How dispatch works

`ELL_API_STYLE` selects a directory under `llm_backends/`:

```
llm_backends/${ELL_API_STYLE}/generate_completion.sh
```

That file is sourced and must define a shell function `generate_completion`.
`ELL_API_STYLE` is validated to a single path segment (`[A-Za-z0-9._-]`, not
`.`/`..`), so it cannot be used to source an arbitrary file by path traversal;
an unknown style is a fatal error.

## The `generate_completion` contract

`generate_completion` is invoked as a pipeline stage:

- **stdin**: the JSON request body ell built from the template.
- **stdout**: the assistant's text completion (only the text, no JSON).
- **stderr**: diagnostics and usage logging (via the `logging_*` helpers).
- **exit status**: `0` on success; non-zero on failure. The bundled backends
  use these distinct codes, and ell propagates them:
  - `3` — the response contained no usable content (empty/unparsable).
  - `4` — the completion finished abnormally (e.g. truncated: `length` /
    `MAX_TOKENS`, or a content filter), so it must not be reported as success.
  - the curl exit code — a transport failure (propagated as-is).

Backends honour `ELL_API_STREAM` (`true`/`false`) to choose between a streaming
and a single-response request.

## HTTP requests: use `ell_curl`

Backends should make requests through `ell_curl` (in `llm_backends/http.sh`)
rather than calling `curl` directly, so they inherit ell's shared behaviour:

- connection/overall timeouts (`ELL_CONNECT_TIMEOUT`, `ELL_MAX_TIME`);
- HTTP error handling (`--fail-with-body` / `--fail`), so a 4xx/5xx becomes a
  non-zero exit instead of a silent empty body;
- credentials kept off the command line: set `ELL_CURL_AUTH_HEADER` (e.g.
  `Authorization: Bearer ${ELL_API_KEY}`) and `ell_curl` passes it via a
  `--config` file, so the key is not visible in `ps` / `/proc`;
- a refusal to send credentials over plaintext `http://` remotes unless
  `ELL_ALLOW_INSECURE_URL=true` (see [Risk Consideration](Risk_Consideration.md)).

Pass the request body with `--data-binary @-` so it is read from stdin.

## Writing a custom backend

1. Create `llm_backends/<style>/generate_completion.sh` (under any of the search
   roots — your XDG config dir works too).
2. Source the HTTP helper and define `generate_completion`:

   ```bash
   #!/usr/bin/env bash
   . "$(dirname "${BASH_SOURCE[0]}")/../http.sh";

   generate_completion() {
     local ELL_CURL_AUTH_HEADER="Authorization: Bearer ${ELL_API_KEY}";
     export ELL_CURL_AUTH_HEADER;
     # Read the JSON body from stdin, call the API, print the text to stdout.
     ell_curl "${ELL_API_URL}" \
       --header "Content-Type: application/json" \
       --data-binary @- \
       | # ...parse the response (see helpers/json.sh) and print the text...
   }
   export -f generate_completion;
   ```

3. Add a matching template (see [Templates](Templates.md)) and select the
   backend with `--api-style <style>` (or `ELL_API_STYLE`).

Parse responses with the bundled pure-bash JSON helpers in `helpers/json.sh`
(`json_parse`, `json_get`, `json_has`) so no external `jq` dependency is needed.
