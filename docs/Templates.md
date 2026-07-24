# Templates

Templates are used to generate the payload sent to the language model. They are written in JSON format and can be customized by users. Templates are where you set the prompt text and other parameters for the language model.

The following variables can be used in templates and are substituted by ell
when the request payload is built:

- `$USER_PROMPT`: The prompt text given by the user.
- `$SHELL_CONTEXT`: The recorded terminal context. This is only populated when
  the session is started with `-r` / `--record` (or in interactive mode).
- `$ELL_LLM_MODEL`: The model name (e.g. from `-m` / `ELL_LLM_MODEL`).
- `$ELL_LLM_TEMPERATURE`: The sampling temperature.
- `$ELL_LLM_MAX_TOKENS`: The maximum number of tokens to generate.
- `$ELL_API_STREAM`: Whether streaming is enabled (`true`/`false`).

`$USER_PROMPT`, `$SHELL_CONTEXT` and `$ELL_LLM_MODEL` are inserted as JSON
strings (their values are JSON-escaped), so you must wrap them in double quotes
in the template. `$ELL_LLM_TEMPERATURE`, `$ELL_LLM_MAX_TOKENS` and
`$ELL_API_STREAM` are inserted verbatim as JSON numbers/booleans, so they must
not be quoted. Any other `${...}` sequence is left untouched: template contents
are treated as data and are never evaluated by the shell.

Here's an example template for openai style API:

```json
{
  "model": "${ELL_LLM_MODEL}",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant. "
    },
    {
      "role": "user",
      "content": "${SHELL_CONTEXT}\n\n---\n\n${USER_PROMPT}"
    }
  ],
  "temperature": ${ELL_LLM_TEMPERATURE},
  "max_tokens": ${ELL_LLM_MAX_TOKENS},
  "stream": ${ELL_API_STREAM}
}
```

Here's an example template for gemini style API:

```json
{
  "contents": [
    {
      "role": "user",
      "parts": [
        {
          "text": "You are a helpful assistant. ${SHELL_CONTEXT}\n\n---\n\n${USER_PROMPT}"
        }
      ]
    }
  ]
}
```

An example of an interactive LLM application can be found in `templates/ctf-gemini.json` and `templates/ctf-openai.json`.

Regarding the use of plugins, please refer to the API documents of the respective language model provider.