# Plugins
## Overview

The plugin system is designed to enrich the user experience and extend the functionality of ell, while keeping the code modular and flexible.

The term "plugin" here means a script that can be called by ell. It can be used to extend ell's functionality. The plugins supported by LLM providers are not included here. Please refer to [Templates](Templates.md).

## Built-in Plugins

Built-in plugins are available in the `./plugins` directory of the ell repository: 

- **redaction**: Redacts sensitive information.
- **paginator**: Paginates the output.
- **syntax_highlight**: Syntax highlights the output.

The "redaction" plugin is disabled by default because it is a best-effort
control that can also mangle legitimate input. Its hook script therefore ships
as `plugins/redaction/50_post_input.sh.disabled`. Any hook script whose name
contains `.disabled` is ignored by the plugin loader, so to enable redaction
remove the `.disabled` suffix (rename it back to `50_post_input.sh`); to disable
any other plugin, add a `.disabled` suffix to its hook script.

## Writing Plugins

Ell supports plugins to extend its functionality through a hook system. Currently, the following hooks are available:

- `post_input`: Called after the user prompt is received.
- `pre_llm`: Called before the payload is sent to the language model.
- `post_llm`: Called after the response is received and decoded from the language model.
- `pre_output`: Called before the output is sent to the user.

Plugins are discovered from the `plugins/` directory under each of the
following roots, searched in this priority order:

- `${XDG_CONFIG_HOME:-$HOME/.config}/ell/plugins/` (your own plugins)
- `${XDG_DATA_HOME:-$HOME/.local/share}/ell/plugins/`
- `~/.ellrc.d/plugins/` (legacy location, still supported)
- the `plugins/` directory bundled with ell (built-in plugins)

If the same plugin hook (identified by `<plugin-dir>/<hook-file>`) exists in
more than one root, only the highest-priority copy runs, so you can drop a
plugin with the same name under your XDG config directory to override a
built-in one.

Each plugin should be a folder containing executable shell scripts. The file name should follow the format `XX_${HOOK_NAME}.sh`, where `XX` is a number that determines the execution order among other plugins. For example, the built-in paginator plugin is placed in `plugins/paginator/90_pre_output.sh` (so a user copy would live at `${XDG_CONFIG_HOME:-$HOME/.config}/ell/plugins/paginator/90_pre_output.sh`).

Plugin scripts are executed in ascending numerical order (across all roots, ordered by `<plugin-dir>/<hook-file>`) and piped to each other.

It is recommended to write plugins in a streaming manner.

Below is an example of a simple plugin script:

```bash
#!/usr/bin/env bash

cat;
```

This plugin will simply pass the input to the next plugin in the chain.

## Possible Use Cases (not implemented yet)

- **Store dialogues**: Store dialogues into a database or file.
- **Load system secrets**: Load system secrets from a secret manager instead of environment variables or CLI parameters ([#18](https://github.com/simonmysun/ell/issues/18)).
- **Custom redaction**: Implement custom redaction logic or call third-party softwares for desensitization of sensitive information.
- **Custom formatting**: Support more output formatters, e.g. XML, code block formatting, etc.
- **Execute commands**: Semi-automate tasks by executing commands based on the output.

Pull requests are welcome for new plugins or improvements to existing plugins.