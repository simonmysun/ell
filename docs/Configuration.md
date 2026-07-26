# Configuration

## Order of precedence

ell can be configured in three ways (in order of precedence, from lowest to highest):

- configuration files
- environment variables
- command line arguments

The configuration files are read and applied in the following order (later
files override earlier ones):

- `${XDG_CONFIG_HOME:-$HOME/.config}/ell/config` (the main config, following the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html))
- `~/.ellrc` (legacy location, still read for backward compatibility)
- `.ellrc` in the current directory
- `$ELL_CONFIG` specified in the environment variables or command line arguments.

Specifying `ELL_CONFIG` in the file provided with the `-c` / `--config` option will not work since looking for the config file is not recursive.

If you are running ell in a relatively hostile environment, it is recommended to load the environment variables from an encrypted file. This can be done by using a third-party tool. (related issue: [#18](https://github.com/simonmysun/ell/issues/18))

## Configurable variables

The following variables can be set in the configuration files, environment variables:

- `ELL_LOG_LEVEL`: The verbosity of the logger, from `1` (least) to `5` (most). The default is `2`. Higher values enable more output: `1` = fatal only, `2` = errors (default), `3` = warnings, `4` = info (this is the level at which token usage is logged), `5` = debug (everything). A value of `0` disables all logging.
- `ELL_CONFIG`: An extra configuration file to load, applied last (highest precedence among files). Unset by default. The standard config files (`${XDG_CONFIG_HOME:-$HOME/.config}/ell/config`, `~/.ellrc`, `./.ellrc`) are always read regardless of this variable.
- `ELL_LLM_MODEL`: The model to use. Default is `gpt-4o-mini`.
- `ELL_LLM_TEMPERATURE`: The temperature of the model. The default is `0.6`.
- `ELL_LLM_MAX_TOKENS`: The maximum number of tokens to generate. The default is `4096`.
- `ELL_TEMPLATE_PATH`: Force templates to be loaded from this single directory (note the trailing slash, e.g. `/path/to/templates/`). When unset (the default), templates are searched, in order, under `${XDG_CONFIG_HOME:-$HOME/.config}/ell/templates/`, `${XDG_DATA_HOME:-$HOME/.local/share}/ell/templates/`, `~/.ellrc.d/templates/` (legacy) and the `templates/` directory bundled with ell. This lets you override a bundled template by placing a file with the same name under your XDG config directory.
- `ELL_TEMPLATE`: The template to use. The default is `default-openai`. The file extension is not needed.
- `ELL_INPUT_FILE`: The input file to use. If specified, it will override the prompt given in command line arguments. Setting this to `-` will let ell always read from stdin. 
- `ELL_RECORD`: This is used for controlling whether record mode is on. It should be set to `false` unless you want to disable recording.  
- `ELL_OUTPUT_FILE`: The output file to use. If specified, it will redirect stdout to the file. The default is `-`. When in interactive mode and record mode, the terminal history is written to stdout.
- `ELL_INTERACTIVE`: Run ell in interactive mode. The default is `false`.
- `ELL_API_STYLE`: The API style to use. The default is `openai`.
- `ELL_API_KEY`: The API key to use.
- `ELL_API_URL`: The API URL to use.
- `ELL_API_STREAM`: Whether to stream the output. The default is `true`.
- Plugins related variables:
  - `TO_TTY`: Force ell to output with syntax highlighting and pagination or not. 
  - Styling related variables can be found in [Styling](Styling.md).

The following can be set in the command line arguments:

- `-h, --help`: show this help and exit.
- `-V, --version`: show the version and exit.
- `-l, --log-level`: `ELL_LOG_LEVEL`
- `-m, --model`: `ELL_LLM_MODEL`
- `-T, --template-path`: `ELL_TEMPLATE_PATH`
- `-t, --template`: `ELL_TEMPLATE`
- `-f, --input-file`: `ELL_INPUT_FILE`
- `-r, --record`: sets `ELL_RECORD` to true. This will ignore the prompt input or the file input.
- `-i, --interactive`: `ELL_INTERACTIVE`.  This will ignore the prompt input or the file input.
- `-o, --output, --output-file`: `ELL_OUTPUT_FILE`
- `--api-style`: `ELL_API_STYLE`
- `--api-key`: `ELL_API_KEY`, note that in multi-user environments, other users are able to see the command line arguments.
- `--api-url`: `ELL_API_URL`
- `--api-disable-streaming`: sets `ELL_API_STREAM` to **false**
- `-c, --config`: `ELL_CONFIG`
- `-O, --option`: Set extra environment variables for the run. The format is `A=b` or `C=d,E=f`. The key must be a valid shell variable name. These variables are exported into ell's environment (so plugins and backends can read them), but note that **they are not substituted into templates**: the template renderer only substitutes a fixed allowlist of placeholders (see [Templates](Templates.md)). Under the previous `eval`-based renderer arbitrary `-O` variables did appear in templates; that behavior was removed with the switch to safe, allowlist-only rendering.

OpenAI and Gemini style APIs are supported out of the box (plus an `ell_echo`
debugging backend). You can add your own — see [Backends](Backends.md).

## Windows

ell runs on Windows from any Bash environment (Git Bash, MSYS2, Cygwin, WSL),
but these environments emulate a POSIX system to different degrees. Two behaviors
depend on facilities that **Git Bash does not provide over NTFS**, and they
degrade there:

### Config file trust check (security limitation)

Config files (`${XDG_CONFIG_HOME:-$HOME/.config}/ell/config`, `~/.ellrc`,
`$PWD/.ellrc`, `$ELL_CONFIG`) are **sourced**, i.e. executed as shell code. To
avoid running attacker-controlled code, `load_config` refuses to source a file
that is not owned by the current user/root or that is writable by group or
others (see [Risk Consideration](Risk_Consideration.md)).

This check relies on POSIX ownership and permission bits. On **Git Bash** over
NTFS, `chmod` cannot create genuinely group/world-writable files and `stat` does
not report reliable permission bits, so **the check cannot distinguish a safe
config from an insecure one and effectively cannot protect you there**. On a
shared/multi-user Windows machine, do not rely on this protection under Git Bash;
use **WSL** or **MSYS2/Cygwin** (which back permissions with NTFS ACLs), or keep
your config on a volume only you can write.

The temporary file ell uses to pass the API key to `curl` is likewise
`chmod 600`ed to keep the credential owner-only; that too is not enforceable
under Git Bash.

### Symbolic links and record mode

- Installing `ell` by **symlink** and record mode's terminal capture
  (`script(1)`) both require capabilities Git Bash lacks by default (real
  symlinks need Developer Mode / admin; `script` is not shipped). ell itself is
  a plain wrapper script, so normal use does not need symlinks; MSYS2 and WSL
  provide both when you need them.

### Test suite

The test suite detects these limitations at runtime and prints `SKIP:` for the
affected checks under Git Bash rather than failing, so the informational Windows
CI run stays meaningful. CI also runs the suite under a fuller **MSYS2**
environment, where these features are available and the checks run normally.