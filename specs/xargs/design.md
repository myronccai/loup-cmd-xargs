# Design: xargs

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses the options,
prints any warnings, and calls `commands.xargs.run_xargs`. That reads all of
standard input, splits it (`read_input`), groups the arguments into command
lines (`build_plan`, a pure function) and runs them in order (`run_plan`).

## Modules

| Module | Contents |
|---|---|
| `source/main.loup` | entry point: `run(runtime.args())` |
| `source/appinfo.loup` | name, version, summary, exit statuses 0, 1, 123–127 |
| `source/cli/args.loup` | `Options`, getopt-style `parse_args`, `parse_count`, `parse_delimiter`, the mutually exclusive option warnings |
| `source/cli/usage.loup` | `usage()` help text, `version_line()` |
| `source/cli/app.loup` | `run()`: parse, help/version, warnings, `run_xargs`, exceptions to status 1 |
| `source/commands/input.loup` | `Input` (arguments grouped into logical lines, and an error), `read_words` (core.shlex per line), `unmatched_quote`, `read_lines` and `unquote_line` (-I), `read_delimited` (-0, -d) |
| `source/commands/xargs.loup` | `Plan`, `build_plan`, `line_size`, `replace_all`, `locate`, `check_runnable`, `with_null_stdin`, `run_command`, `run_plan`, `run_xargs` |

### Input

`Input.lines` is a list of logical lines, each a list of arguments: -L
counts them, the other modes flatten them. In the default mode each physical
line goes through `core.shlex.split`; before that, `unmatched_quote` scans
the line with the same rules to find a quote that is never closed, so that
the words before it can still be used and the error names the quote. A line
ending in a blank, or one with no words, does not end the logical line.

### Planning

`build_plan(opts, input)` returns every command line as a list of words,
plus an error when one could not be built (`argument line too long`, or the
command alone exceeding -s). It applies, in order: -I (one command per line,
replacement in the initial arguments), then the -s byte limit, -n and -L.

### Running

`run_plan` prints each command line with `core.shlex.join` when -t is on,
checks once that the command exists and is executable (`locate` on PATH,
`isDir`, and `test -x` through `io.proc.exitCode`, since io.fs has no
`stat()`), then runs each line with the prelude `exec`, wrapped as
`sh -c 'exec "$@" < /dev/null' sh WORDS...` because the runtime cannot
redirect a child's standard input. The wrapper `exec`s the command, so its
exit status and signals come back unchanged; the runtime reports a signal N
as 128 + N. The captured output is printed when the command ends.

`exec`'s result fields are read in `run_command` itself: a `ProcResult`
passed between functions (including `io.proc.run`'s) does not lower in the
native build.

## Differences from the original

- Standard input is read whole before anything runs (T2); no `-p`.
- Quoting follows `core.shlex` per line: `\"` and `\\` are escapes inside
  double quotes, and a backslash-newline does not join lines.
- `-t` uses `core.shlex.join` quoting.
- Output of commands is collected and printed when they end (UTF-8 text).
- Statuses 129–254 from a command are taken as signals.
- `-s` is capped at 2097152 silently.
- Not implemented: `-a`, `-E`, `-e`, `-i`, `-l`, `-x`, `-P`, `-o`, `-p`,
  `--show-limits`, `--process-slot-var`.

## Error handling

Option errors are `Result` errors from `parse_args`, printed by `run()` with
the usage hint (not for a bad `-d` value, as GNU) and status 1. Input and
size errors are printed before the commands run and give status 1 unless a
command stops xargs with 124–127. An unexpected exception is printed and
gives status 1.

## Testing

- `tests/args_test.loup`: bundling, attached values, long options, `--`,
  warnings, every option error, numbers, delimiter escapes.
- `tests/input_test.loup`: line handling, quotes, unmatched quotes, -I
  lines, delimited input.
- `tests/xargs_test.loup`: `build_plan` for every grouping option, empty
  input, -r, size limits, the replacement string, the stdin wrapper.
- `tests/app_test.loup`: exit statuses through `run()` (no processes).
- `tests/e2e.sh`: the native binary on prepared input: every option, -t
  output, child output and standard input, every exit status 123–127,
  size errors, warnings and option errors.
