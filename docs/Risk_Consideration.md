# Risk Consideration

The following risks should be considered when using ell:

## Sending data to LLM backends

- The prompts are sent to LLM backends, so be careful with sensitive information.
  - A redaction plugin ([#14](https://github.com/simonmysun/ell/issues/14)) is
    available to redact sensitive information, but it is not foolproof. For
    enhanced desensitization, use your own plugin or call third-party softwares.
    The redaction plugin ships **disabled by default** (its hook script has a
    `.disabled` suffix); enable it by removing that suffix. See
    [Plugins](Plugins.md).
  - In record/interactive mode, the recorded terminal context (`$SHELL_CONTEXT`)
    is also sent to the backend. It is passed through the same `post_input` hooks
    as your prompt, so redaction applies to it too when enabled.
- The output of LLMs is not guaranteed to be correct or safe. An LLM can be
  tuned or prompted to return deceptive results, e.g. instructions that
  manipulate your terminal.

## Executable content: templates, plugins and config

ell treats templates, plugins and config files as **code**, not just data.
Installing them from untrusted sources runs arbitrary commands as your user:

- **Plugins** are shell scripts executed as you. Only install plugins you trust.
- **Config files** are sourced (executed). ell only sources a config file that
  is owned by you (or root) and is not group-/world-writable, which blocks the
  "hostile `.ellrc` in the current directory" attack, but a config file *you*
  own can still run anything you put in it.
- **Templates** are substituted with a fixed allowlist of variables and are
  **not** evaluated by the shell, so a template file cannot execute commands.
  Values you supply (prompt, model, etc.) are inserted as data. Older, unrelated
  "install a template" advice from third parties should still be treated with
  care.
- `ELL_API_STYLE` and template names are validated so they cannot be used to
  load arbitrary files by path traversal.

## Credentials

- Passing `--api-key` on the command line is discouraged: it ends up in your
  shell history. Prefer a config file (with safe permissions) or the
  environment. The key is not logged and is not placed on curl's command line.
- By default ell refuses to send credentials to a plaintext `http://` URL (only
  `https://` and loopback hosts are allowed) to avoid leaking the key in
  cleartext. Set `ELL_ALLOW_INSECURE_URL=true` to override for a trusted local
  endpoint.

## Record mode

- In record mode, all your input and output history are written to
  `/tmp/tmp.xxxx` and are readable by the root user.
- Unexpected exit of record mode may leave the history file in `/tmp/`.
- Password input is not recorded by `script`, so it is safe to type sudo or ssh
  passwords in the terminal.