# Lint suite

Static analysis for the Godot 4.7.x project. No Godot binary needed
to develop new checks; just a plain text editor and the project's
existing `lint_helpers.gd`.

## Running

From `game/`:

```bash
tests/lint/run_all.sh
# or, with a custom Godot binary:
tests/lint/run_all.sh /path/to/Godot
# or:
GODOT=/path/to/Godot tests/lint/run_all.sh
```

Or run any single test directly:

```bash
godot --headless --path . --script res://tests/lint/test_lint_autoload.gd
```

## Tests

| Test | What it catches |
|------|-----------------|
| `test_lint_autoload.gd` | autoload/class_name collisions, missing autoload scripts, cyclic preloads, missing preload targets, true self-preloads (the `__Foo__` idiom is allowed) |
| `test_lint_indentation.gd` | files using leading spaces (project policy is tabs), mixed tab/space files, trailing whitespace, suspicious indent jumps |
| `test_lint_syntax.gd` | CRLF line endings, UTF-8 BOM, unbalanced brackets/parens, `class_name` before `extends`, 3+ consecutive blank lines |
| `test_lint_charset.gd` | non-ASCII bytes (em-dash, smart quotes, NBSP, etc.); specific named offenders get a replacement suggestion |
| `test_lint_general.gd` | orphan .uid files, missing .tscn resources, hardcoded absolute paths, `print()` in non-test code, mixed tabs/spaces on a line, 200+ col lines, `@tool` scripts, `TODO`/`FIXME`/`XXX`/`HACK`/`BUG` markers in comments, empty function bodies (stubs), 500+ line files, `assert()` in non-test code |

Each test exits 0 on success and 1 on failure. Errors and warnings
are printed to stdout in a uniform `<file>:<line>: <severity>: <message>`
format so the runner can aggregate them.

## Allowlists

- `test_lint_autoload.gd` has a single allowlist entry: `QoSService`,
  which intentionally has both a class_name and an autoload. The
  class_name provides static shim methods that resolve the autoload
  at runtime. See `game/core/autoload/qos_service.gd`. Add new
  entries with a one-line comment explaining why.
- All linters skip `res://addons/` (third-party code).
- All linters skip `res://tests/` for the `print()` check (tests
  are allowed to print).

## Adding a check

1. Decide which test file it belongs in. If none fit, add a new one.
2. Add a small `_check_<thing>()` function to that test.
3. Call it from `_init()`.
4. Use `_ok(label)` for pass, `_fail(label, detail)` for fail, and
   `Helpers.report_issue(file, line, severity, message)` for
   per-file reports. Severity is `error` / `warning` / `info`.
5. Re-run `run_all.sh` to verify.

## Verifying with a smoke fixture

When you change a linter's logic, drop a small fixture file in
this directory (e.g., `_smoke_<feature>.gd`) with each known bug
clearly marked with a `# BUG:` comment, run the linter, and
confirm every `BUG:` was caught. Delete the fixture afterward.

The last smoke run caught:

- `test_lint_indentation.gd`: mixed leading tabs+spaces
- `test_lint_syntax.gd`: CRLF line endings, unclosed `[`
- `test_lint_charset.gd`: 60+ non-ASCII bytes, named em-dash
- `test_lint_general.gd`: hardcoded `/tmp/` path, mixed leading
  tabs+spaces on a line

`test_lint_autoload.gd` does not run against files in
`tests/lint/` (it skips its own directory to avoid the linter
shadowing itself). Verify that linter by introducing a temporary
collision in `game/core/schemas/` or similar and reverting.

## Limitations

These are static checks. They catch a wide class of issues without
booting the project, but they cannot replace a real compile pass
for things like:

- Type-mismatch errors
- Undefined identifiers (we check class_name collisions but not
  every reference to every class)
- Signal/callable signature mismatches (we count call sites but
  do not parse types)
- Runtime behavior (autoload order issues at startup, etc.)

For those, run the project's full smoke tests under a real
Godot binary.
