# Risk Consideration

The following risks should be considered when using ell:

- The prompts are sent to LLM backends, so be careful with sensitive information.
- The output of LLMs is not guaranteed to be correct or safe.
- In record mode, all your input and output history are written to `/tmp/tmp.xxxx` and are readable by root user. 
- LLM can be tuned or prompted to return deceptive results, e.g. manipulating your terminal
- Unexpected exit of record mode may cause the history file to remain in `/tmp/`.
- Password input is not recorded by `script`, so it is safe to type sudo or ssh passwords in terminal.