# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

This is a large hardening pass focused on security, robustness, and testing.

### Security

- Templates are no longer rendered through the shell. Previously template
  contents were run through `eval`, so a template (or a prompt / recorded
  context interpolated into one) could execute arbitrary commands. Rendering is
  now a strict allowlist substitution with JSON escaping and no shell
  evaluation.
- `-O KEY=VALUE` no longer runs through `eval`. It is assigned directly and the
  key is validated, closing a command-injection hole (`-O 'X=$(cmd)'`).
  Note: as a consequence of the safe, allowlist-only template renderer, variables
  set via `-O` are exported into the environment but are **no longer substituted
  into templates** (the old `eval` renderer did expand them). Only the fixed
  placeholder allowlist is rendered.
- Config files are only sourced when trusted: owned by the current user (or
  root) and not group-/world-writable. This blocks the "hostile `.ellrc` in the
  current directory" arbitrary-code-execution vector. Refusals are now reported
  at a visible log level.
- `ELL_API_STYLE` and template names are validated as single path segments, so
  they cannot be used to source/load arbitrary files by path traversal.
- The recorded terminal context (`SHELL_CONTEXT`) now passes through the
  `post_input` hooks, so redaction applies to it too, not just the prompt.
- The API key is kept out of the process table: it is passed to curl via a
  `--config` file (mode 0600, removed after use) instead of a `--header`
  argument, and it is no longer logged at debug level.
- ell refuses to send credentials to a plaintext `http://` URL (loopback
  excepted); override with `ELL_ALLOW_INSECURE_URL=true`.
- The bundled redaction plugin now ships **disabled by default** (its hook has a
  `.disabled` suffix); enable it by removing the suffix.

### Fixed

- Streaming completions that finish abnormally (e.g. `length` / `MAX_TOKENS`)
  are now detected and reported as failures instead of silent success
  (openai read the finish reason from the wrong path).
- A value-taking option given with no argument (e.g. `ell -m`) no longer causes
  an infinite loop; it exits with a usage error.
- Interactive mode exits cleanly on EOF (Ctrl-D) instead of looping forever, and
  a final unterminated line is still processed. The exit hint now names Ctrl-D.
- `-o`/`--output` is accepted as documented (previously only `--output-file`),
  and output is no longer redirected to a file in record/interactive mode (an
  always-true comparison was fixed).
- The `--record` "already enabled" guard now works, and `ELL_RECORD` is
  exported like the other flags.
- Record mode re-execs ell by an absolute, shell-quoted path, so it works when
  ell is run in place or is not on `PATH`.
- Template resolution rejects path-traversal names and accepts an
  `ELL_TEMPLATE_PATH` with or without a trailing slash; plugin-hook discovery no
  longer breaks on paths containing spaces/newlines.
- Missing `ELL_API_URL` now fails early with a clear, actionable message
  (EX_CONFIG) instead of an opaque curl error; a missing `ELL_API_KEY` warns.
- curl failures are reported with a human-readable explanation (DNS, connection
  refused, timeout, TLS, …) rather than a bare exit code.
- Functions are exported with `export -f` rather than as empty variables.
- Bash 4.1 compatibility is restored (the version gate, docs and CI now
  consistently target 4.1).

### Changed

- HTTP requests go through a shared `ell_curl` wrapper with connection/overall
  timeouts (`ELL_CONNECT_TIMEOUT`, `ELL_MAX_TIME`) and HTTP error handling
  (`--fail-with-body`), so a stalled server no longer hangs and a 4xx/5xx no
  longer surfaces as a vague "Unexpected format".
- The openai and gemini backends share their non-streaming path, end-of-stream
  reporting and PIPESTATUS handling via `helpers/backend_common.sh`; each keeps
  only its provider-specific streaming parser.
- `helpers/http.sh` moved out of `llm_backends/` for consistency with the other
  helpers.
- The default log level is unified across entry points.

### Performance

- The pure-bash JSON parser copies runs of ordinary string characters in one
  operation and no longer forks a subshell per key lookup.
- The gemini streaming parser tracks JSON object boundaries instead of
  re-parsing the whole accumulated buffer per line (was O(n²)).
- Streaming loops use bash builtins instead of a `grep`/`cut`/`tr` subprocess
  per line, and logging no longer forks `date`/`basename` per line.

### Added

- Documentation: `docs/Architecture.md`, `docs/Backends.md`, expanded
  `docs/Templates.md` and `docs/Risk_Consideration.md`, and this changelog.
- Extensive test coverage: unit tests for argument parsing, config loading, path
  resolution, the HTTP helper, template rendering, the JSON parser, logging, the
  syntax-highlight and paginator plugins; and end-to-end tests for the request
  pipeline, hook stages, interactive mode, output redirection, error paths, the
  launcher, record mode, the bash version gate and terminal-size fallback.

## [0.1.1]

- Baseline release prior to the hardening pass above.
