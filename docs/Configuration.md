# Configuration

## Order of precedence

ell can be configured in three ways (in order of precedence, from lowest to highest):

- configuration files
- environment variables
- command line arguments

The configuration files are read and applied in the following order:

- `~/.ellrc`
- `.ellrc` in the current directory
- `$ELL_CONFIG` specified in the environment variables or command line arguments.

Specifying `ELL_CONFIG` in the file provided with the `-c` / `--config` option will not work since looking for the config file is not recursive.

## Configurable variables

The following variables can be set in the configuration files, environment variables:

- `ELL_LOG_LEVEL`: The log level of the logger. The default is `2`. A log level of `0` will log everything. A log level of `3` will log token usage.
- `ELL_CONFIG`: The configuration file to use. The default is `~/.ellrc`.
- `ELL_LLM_MODEL`: The model to use. Default is `gpt-4o-mini`.
- `ELL_LLM_TEMPERATURE`: The temperature of the model. The default is `0.6`.
- `ELL_LLM_MAX_TOKENS`: The maximum number of tokens to generate. The default is `4096`.
- `ELL_TEMPLATE_PATH`: The path to the templates. The default is `~/.ellrc.d/templates`.
- `ELL_TEMPLATE`: The template to use. The default is `default`. The file extension is not needed.
- `ELL_INPUT_FILE`: The input file to use. If specified, it will override the prompt given in command line arguments.
- `ELL_RECORD`: This is used for controlling whether record mode is on. It should be set to `false` unless you want to disable recording.  
- `ELL_INTERACTIVE`: Run ell in interactive mode. The default is `false`.
- `ELL_API_STYLE`: The API style to use. The default is `openai`.
- `ELL_API_KEY`: The API key to use.
- `ELL_API_URL`: The API URL to use.
- `ELL_API_STREAM`: Whether to stream the output. The default is `true`.
- Plugins related variables:
  - `TO_TTY`: Force ell to output with syntax highlighting and pagination or not. 
  - Styling related variables can be found in [Styling](docs/Styling.md).

The following variables can be set in the command line arguments:
  -h, --help: show this help

- `-l, --log-level`: `ELL_LOG_LEVEL`
- `-m, --model`: `ELL_LLM_MODEL`
- `-T, --template-path`: `ELL_TEMPLATE_PATH`
- `-t, --template`: `ELL_TEMPLATE`
- `-f, --input-file`: `ELL_INPUT_FILE`
- `-r, --record`: sets `ELL_RECORD` to true. This will ignore the prompt input or the file input.
- `-i, --interactive`: `ELL_INTERACTIVE`.  This will ignore the prompt input or the file input.
- `--api-style`: `ELL_API_STYLE`
- `--api-key`: `ELL_API_KEY`
- `--api-url`: `ELL_API_URL`
- `--api-disable-streaming`: sets `ELL_API_STREAM` to **false**
- `-c, --config`: `ELL_CONFIG`
- `-o, --option`: Other options. The format is `A=b` or `C=d,E=f`.

Currently, only OpenAI style API is supported. More API styles are coming soon.