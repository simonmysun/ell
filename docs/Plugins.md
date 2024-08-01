# Plugins

Ell supports plugins to extend its functionality through a hook system. Currently, the following hooks are available:

- `post_input`: Called after the user prompt is received.
- `pre_llm`: Called before the payload is sent to the language model.
- `post_llm`: Called after the response is received and decoded from the language model.
- `pre_output`: Called before the output is sent to the user.

Plugins should be placed in the `./plugins` directory related to the ell script, typically located at `~/.ellrc.d/plugins` if you follow the installation instructions in the readme. 

Each plugin should be a folder containing executable shell scripts. The file name should follow the format `XX_${HOOK_NAME}.sh`, where `XX` is a number that determines the execution order among other plugins. For example, the paginator plugin is placed in `~/.ellrc.d/plugins/paginator/90_pre_output.sh`.

Plugin scripts are executed in ascending numerical order and piped to each other.

It is recommended to write plugins in a streaming manner.

Below is an example of a simple plugin script:

```bash
#!/usr/bin/env bash

cat;
```

This plugin will simply pass the input to the next plugin in the chain.
