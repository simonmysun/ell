# Templates

Templates are used to generate the payload sent to the language model. They are written in JSON format and can be customized by users. Templates are where you set the prompt text and other parameters for the language model.

Currently, there are two variables that can be used in the templates, except the ones given by users:

- `$SHELL_CONTEXT`: The context of the shell. This only works when the shell is started with `-r` or `--record`.
- `$USER_PROMPT`: The prompt text given by the user.

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