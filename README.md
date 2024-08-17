# ell

A command-line interface for LLMs written in Bash.

## Features

<video src="https://github.com/user-attachments/assets/dce8ce33-c948-4db3-83db-8f8e2f1cb6a1"></video>

*Basic usage of ell (webm, 1,6MiB)*

- Ask LLMs from your terminal
- Pipe friendly
- Bring your terminal context to the LLMs and ask questions
- Chat with LLMs in your terminal
- Function calling and more supported via templates.

## Requirements

To use ell, you need the following:

- bash version 4.1 or later
- jq (For parsing JSON)
- curl (For sending HTTPS requests)
- perl (For PCRE. POSIX bash doesn't support look-ahead and look-behind regex. Not necessary if you don't use record mode)

## Install

```
git clone --depth 1 https://github.com/simonmysun/ell.git ~/.ellrc.d
echo 'export PATH="${HOME}/.ellrc.d:${PATH}"' >> ~/.bashrc
```

or

```
git clone --depth 1 git@github.com:simonmysun/ell.git ~/.ellrc.d
echo 'export PATH="${HOME}/.ellrc.d:${PATH}"' >> ~/.bashrc
```

This will clone the repository into `.ellrc.d` in your home directory and add it to your PATH. 

## Configuration

See [Configuration](docs/Configuration.md).

Here's an example configuration to use `gemini-1.5-flash` from Google. You need to set these variables in your `~/.ellrc`:

```ini
ELL_API_STYLE=gemini
ELL_LLM_MODEL=gemini-1.5-flash
ELL_TEMPLATE=default-gemini
ELL_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ELL_API_URL=https://generativelanguage.googleapis.com/v1beta/models/
```

Here's an example configuration to use `gpt-4o-mini` from OpenAI. 

```ini
ELL_API_STYLE=openai
ELL_LLM_MODEL=gpt-4o-mini
ELL_TEMPLATE=default-openai
ELL_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ELL_API_URL=https://api.openai.com/v1/chat/completions
```

## Usage examples

Make sure you have configured correctly.

Ask a question:

```bash
ell "What is the capital of France?"
```

Specify a model and use a file as input:

```bash
ell -m gpt-4o -f user_prompt.txt
```

reading from stdin is also supported:

```bash
cat somecode.py | ell -f -
```

If you prefer add another piece of prompt instantly instead of adding it in the template:

```bash
(cat somecode.py; echo "Explain this code") | ell -f -
```

Record terminal input and output and use as context:

```bash
ell -r
# do random stuff
ell What does the error code mean?
ell How to fix it?
```

Run in interactive mode:

```bash
ell -i
```

In interactive mode, record mode is automatically enabled to allow you chat with context.

Specify a template and start in record mode and interactive mode:

```bash
ell -r -i -t ctf-gemini
```
or
```bash
ell -r -i -t ctf-openai
```
depends on which API you are using.

<video src="https://github.com/user-attachments/assets/afb85632-fa0e-405e-afd8-57d22bd9439d"></video>

*Example application of a capture the flag game (webm, 2.6MiB)*

## Writing Templates

See [Templates](docs/Templates.md).

Note that the use of the plugin support of LLM providers in ell is made with templates.

## Styling

See [Styling](docs/Styling.md).

## Plugins

See [Plugins](docs/Plugins.md).

The term "Plugin" here means a script that can be called by ell. It can be used to extend ell's functionality. The plugins supported by LLM providers is not included here. Please refer to [Templates](docs/Templates.md).

## Risks to consider

See [Risks Consideration](docs/Risk_Consideration.md).

## FAQ

- **Q**: Why is it called "ell"?
- **A**: "ell" is a combination of shell and LLM. It is a shell script to use LLM backends. "shellm" was once considered, but it was dropped because it could be misunderstood as "she llm". "ell" is shorter, easy to type and easy to remember. It does not conflict with any active software. Note that the name "shell" of shell scripts is because it is the outer layer of the operating system exposed to the user. It doesn't indicate that it is a CLI or GUI. Unfortunately it cannot be shortened to "L" which has the same pronunciation because that would conflict with too many things. 


- **Q**: Why is it written in Bash?
- **A**: Because Bash is the most common shell on Unix-like systems and there is just no need to use a more complex language for this.


- **Q**: What is the difference between ell and other similar projects?
- **A**: ell is written in almost pure Bash, which makes it very lightweight and easy to install. It is also very easy to extend and modify. It is pipe-friendly, which means it is designed to be used in combination with other tools. 

## Similar Projects

- https://github.com/kardolus/chatgpt-cli - A CLI for ChatGPT written in Go. 
- https://github.com/kharvd/gpt-cli A CLI for various LLM backends written in Python. 
- https://github.com/JohannLai/gptcli A CLI for OpenAI LLMs written in TypeScript.
- https://github.com/x-cmd/x-cmd A huge collection of various tools which includes a CLI for LLM APIs. The project is written in POSIX bash and awk.
- https://github.com/llimllib/gpt-bash-cli A CLI for OpenAI API that saves the requests and responses into a database. It also uses the system keyring to store the API key, which is a lot more secure. This project is also written in bash.
- https://github.com/charmbracelet/mods A CLI tool to talk to LLMs written in Go. It has rich features in conversation management.
- https://github.com/hiquest/nicechat A CLI chat interface for OpenAI models, written in Node.js. 
- https://github.com/closedloop-technologies/autocomplete-sh A CLI for LLM which uses completion to interact with users. It also acquires several history operations to provide better suggestions, also written in bash.
- https://github.com/plandex-ai/plandex A CLI tool to develop AI-integrated workflow, written in Go.
- https://github.com/simonw/llm A CLI tool for in-depth manipulation of LLMs, written in Python.
- https://github.com/sigoden/aichat A CLI tool talks to various LLM providers, written in Rust.

## Contributing

Contributions are welcome! If you have any ideas, suggestions, or bug reports, please open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.