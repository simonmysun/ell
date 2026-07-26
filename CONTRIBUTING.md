# Contributing

Contributions are welcome — issues, suggestions, and pull requests. This guide
covers the coding conventions and the test suite. For how the code is
organised, see [docs/Architecture.md](docs/Architecture.md).

## Coding conventions

ell is deliberately dependency-light bash. A few conventions keep it portable,
fast, and consistent; please follow them:

- **Portability: bash >= 4.1, GNU *and* BSD tools.** The code runs on Linux and
  macOS and under `set -o posix` in the test harness. Avoid bashisms that break
  on 4.1 (e.g. process substitution `< <(...)` under `set -o posix` — use a
  here-string instead), and prefer POSIX-portable tool invocations (`stat`
  already falls back from GNU to BSD form).
- **No per-line subprocesses on hot paths.** Streaming loops and logging must
  not fork `grep`/`cut`/`tr`/`sed`/`date`/`basename` per line/chunk; use bash
  builtins (parameter expansion, `[[ ]]`, `printf -v`, `printf '%(...)T'`).
- **Prefer builtins over external tools** generally, and keep the runtime
  dependency surface small (bash, curl, awk).
- **Quoting and comparisons.** Quote expansions. Use the portable
  `[ "x${VAR}" = "xVALUE" ]` idiom for string comparisons (the `x` prefix guards
  against values that look like operators); reserve `[[ ]]` for where it is
  actually needed (regex `=~`, glob `==`). Use `[ "${n}" -ge N ]` for numbers.
- **Style.** Trailing semicolons on statements, as in the existing code. Keep
  functions small; give private helpers an `_ell_`/`_json_`-style prefix and
  export public functions with `export -f`.
- **Security first.** Never `eval` user-influenced data. Treat templates,
  plugins and config as the trust-sensitive surfaces they are (see
  [docs/Risk_Consideration.md](docs/Risk_Consideration.md)). Keep secrets out of
  argv and logs.
- **Run ShellCheck.** `error`-level findings block CI; keep the diff clean of
  new warnings too.

Every behaviour-changing PR should come with tests, and the full suite must
pass under both supported bash versions (below).

## Testing

The tests are self-checking Bash scripts: each asserts expected values and
exits non-zero on any failure, so they can gate CI without human inspection.
They use a tiny built-in assertion helper (`tests/assert.sh`) rather than an
external framework, keeping the project dependency-free. The LLM backends are
exercised offline via the `ell_echo` dummy backend and `file://` JSON fixtures,
so no network or API key is required.

### Layout

Tests come in two flavours:

- **Unit tests live next to the source they cover**, named `<source>.test.sh`,
  so a file's tests are easy to find right beside it:

  ```
  helpers/json.sh                        helpers/json.test.sh
  helpers/logging.sh                     helpers/logging.test.sh
  helpers/piping.sh                      helpers/piping.test.sh
  helpers/render_to_text.awk             helpers/render_to_text.test.sh
  plugins/redaction/50_post_input.sh     plugins/redaction/50_post_input.test.sh
  ```

- **End-to-end tests that drive the whole `ell` pipeline** (and their JSON
  fixtures) live in `tests/`, alongside the shared assertion helper
  `tests/assert.sh`.

### Running

Run the whole suite once, on your host:

```bash
bash tests/entry.sh
```

Or run it against the oldest and current supported Bash versions in Docker:

```bash
bash tests/docker.sh
```

`tests/entry.sh` auto-discovers every `*.test.sh` in the repository and then
runs the end-to-end tests. `docker.sh` runs it inside `bash:4.1` and `bash:5.2`
containers and fails if the suite fails under either version.

### Continuous integration

`.github/workflows/ci.yml` runs on every push and pull request:

- **ShellCheck** over all shell scripts. Findings at `error` severity block the
  build; warnings are reported but non-blocking so they can be cleaned up
  incrementally.
- **Tests** across a `bash:4.1` and `bash:5.2` matrix.

### Adding a test

For a unit test, create `<source>.test.sh` next to the file it covers, source
the assertion helper (via a path relative to that location), write assertions,
and end with `assert_summary`. It is picked up automatically by `entry.sh` —
no registration needed:

```bash
#!/usr/bin/env bash
set -o posix;
DIR="$(dirname "${0}")";
# From helpers/ this is ../tests/assert.sh; adjust the depth for other dirs.
. "${DIR}/../tests/assert.sh";
. "${DIR}/my_helper.sh";

assert_equals "adds up" "3" "$((1 + 2))";

assert_summary;
```

End-to-end tests that need JSON fixtures or the full pipeline go in `tests/`
(sourcing `"${DIR}/assert.sh"`) and are registered with an explicit
`run_test tests/<name>.sh` line in `tests/entry.sh`.
