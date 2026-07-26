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
  excepted); override with `ELL_ALLOW_INSECURE_URL=true`. Bracketed IPv6
  loopback (`http://[::1]`, with or without a port) is correctly recognised as
  loopback and allowed.
- When `ELL_API_KEY` is empty the backends now send **no** auth header at all,
  instead of an empty `Authorization: Bearer ` / `x-goog-api-key:`. This matches
  the preflight (which permits running with no key) and avoids the empty header
  wrongly tripping the "refuse credential over `http://`" guard.
- The auth header written to curl's `--config` file now escapes backslashes as
  well as double quotes, so a key/header containing a backslash is passed to
  curl intact instead of being mangled (a lone `\t` etc. was interpreted by
  curl's config parser).
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
  `ELL_TEMPLATE_PATH` with or without a trailing slash. Plugin hooks in paths
  containing spaces/newlines are handled end to end: both discovered
  (`list_plugin_hooks`) and executed -- `piping` now shell-quotes a hook stage
  whose path contains spaces instead of word-splitting it into a "No such file"
  failure.
- Missing `ELL_API_URL` now fails early with a clear, actionable message
  (EX_CONFIG) instead of an opaque curl error; a missing `ELL_API_KEY` warns.
- curl failures are reported with a human-readable explanation (DNS, connection
  refused, timeout, TLS, …) rather than a bare exit code. The non-streaming path
  now propagates curl's real exit code on a transport failure (as the streaming
  path and `docs/Backends.md` already promised) instead of collapsing it to `1`.
- The interactive prompt is printed with `printf` instead of `echo -ne`, whose
  `-n`/`-e` handling is unreliable across shells (`ELL_PS1` already holds real
  escape bytes, matching how `ELL_PS2` is printed).
- Functions are exported with `export -f` rather than as empty variables.
- Bash 4.1 compatibility is restored (the version gate, docs and CI now
  consistently target 4.1). Plugin-hook discovery uses a here-string rather than
  process substitution (`< <(…)`), which is a parse error under `set -o posix`
  on bash 4.1; and the backend dispatcher resolves its directory correctly when
  sourced directly (with `BASE_DIR` unset), not only when launched via ell.sh.
- BSD/macOS toolchain fixes: the syntax-highlight plugin no longer spins into an
  infinite loop under BSD `awk` (it used `awk -F ''`, a GNU-only extension) and
  now uses bash builtins; the redaction plugin's word boundaries work under BSD
  `sed` (which lacks `\b`); and record mode uses the BSD `script(1)` command
  syntax on macOS (`script … file command`) rather than the GNU `-c` form.
- Windows (Git Bash / MSYS) fix: a `file://` URL built from a POSIX path is
  rewritten to the `file:///C:/…` form the native curl understands, so the
  bundled `file://` backend and the offline tests work there.

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
- The syntax-highlight and paginator plugins' per-character loops likewise use
  bash pattern matching / parameter expansion instead of forking `echo | grep`,
  `echo | cut` or `awk` for each character.

### Added

- Documentation: `docs/Architecture.md`, `docs/Backends.md`, expanded
  `docs/Templates.md` and `docs/Risk_Consideration.md`, and this changelog.
- Extensive test coverage: unit tests for argument parsing, config loading, path
  resolution, the HTTP helper, template rendering, the JSON parser, logging, the
  syntax-highlight and paginator plugins; and end-to-end tests for the request
  pipeline, hook stages, interactive mode, output redirection, error paths, the
  launcher, record mode, the bash version gate and terminal-size fallback.
- CI now also runs the suite on macOS (BSD toolchain) and on Windows under both
  Git Bash and a fuller MSYS2 environment. Tests that depend on a facility a
  platform lacks (POSIX permission bits, real symlinks, `script(1)`, an
  isolable `bash`) detect that at runtime and `SKIP` instead of failing.
- The test suite no longer depends on `cmp(1)`/diffutils for byte-exact
  comparisons (it uses a pure-bash comparison), so it runs on minimal
  environments; and CI does not install diffutils, keeping that guarantee under
  test.
- Documentation: a "Windows" section in `docs/Configuration.md` and a README
  note spelling out Git Bash's limitations (the config-trust check and the
  `0600` credential file are not enforceable there) and recommending WSL/MSYS2.

## [0.1.1]

- Baseline release prior to the hardening pass above.
