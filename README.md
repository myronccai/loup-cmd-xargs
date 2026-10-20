# loup-cmd-xargs

GNU `xargs` recreated in [Loup](https://code-craft.ai/references/loup): read
arguments from standard input and run a command with them, with `-n`, `-L`,
`-I`, `-d`, `-0`, `-s`, `-t`, `-r`, shell-style quotes in the input, and GNU's
exit statuses 123–127.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is `host.dual` Loup built as a native binary. It shows running child
processes (`exec`, `io.proc`), splitting input with `core.shlex`, a pure
function that plans the command lines, and mapping child exit statuses.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, and `clang` 17 or later for the native build.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make build                                        # native binary: build/xargs
make ci                                           # check, unit tests, build, end-to-end tests
printf 'a b c' | make run ARGS="-n 1 echo"        # run from source with loup run
```

```text
$ printf 'a b c\nd e\n' | build/xargs
a b c d e
$ printf 'a b c d e\n' | build/xargs -n 2
a b
c d
e
$ echo "one 'two three' four\ five" | build/xargs printf '[%s]\n'
[one]
[two three]
[four five]
$ build/xargs -t -n 1 rm -f < files.txt
rm -f notes.txt
rm -f 'my file.txt'
rm -f report.txt
$ printf 'red\ngreen\n' | build/xargs -I{} echo 'paint it {}, {} again'
paint it red, red again
paint it green, green again
$ printf 'a b\nc\nd e f\n' | build/xargs -L 2
a b c
d e f
$ printf 'x,y,z' | build/xargs -d , -n 1
x
y
z
$ printf 'a b\0c\0' | build/xargs -0 printf '<%s>\n'
<a b>
<c>
$ printf '1\n2\n3\n' | build/xargs -n 1 sh -c 'test $0 != 2'; echo "status $?"
status 123
$ echo x | build/xargs no-such-command; echo "status $?"
xargs: no-such-command: No such file or directory
status 127
$ echo "it's" | build/xargs; echo "status $?"
xargs: unmatched single quote; by default quotes are special to xargs unless you use the -0 option
it
status 1
```

`xargs [OPTION]... [COMMAND [INITIAL-ARGS]...]`; the default command is
`echo`. Options come before the command and may be bundled (`-0t`), with
values attached (`-n2`) or separate (`-n 2`); long forms take
`--name=VALUE`.

| Option | Meaning |
|---|---|
| `-n N`, `--max-args=N` | at most N arguments per command line |
| `-L N`, `--max-lines=N` | the arguments of at most N non-blank input lines per command line; a line ending in a blank continues on the next |
| `-I R` | run the command once per input line, with R in the initial arguments replaced by the line |
| `-d C`, `--delimiter=C` | arguments end at the character C (`\n`, `\t`, `\0`, `\xHH`, `\NNN` escapes); no quote processing |
| `-0`, `--null` | arguments end at NUL; no quote processing |
| `-s N`, `--max-chars=N` | at most N bytes per command line, counting each word and its NUL (default 131072) |
| `-t`, `--verbose` | print each command line on standard error before running it |
| `-r`, `--no-run-if-empty` | do not run the command when there are no arguments |
| `--help`, `--version` | |

`-n`, `-L` and `-I` cancel each other as in GNU xargs: the later one wins,
with a warning.

Exit status: `0` on success; `123` if any run of the command exited with
1–125; `124` if it exited with 255; `125` if it was killed by a signal; `126`
if it cannot be run; `127` if it is not found; `1` for a bad command line, an
unmatched quote or a command line that cannot fit. On 124–127 xargs stops at
once.

## Differences from GNU xargs

- Standard input is read whole before the first command runs (Loup 1.26.0
  has no line-at-a-time reader), so commands start only once the input
  ends. `-p` (prompting) is not implemented for the same reason.
- Quotes in the input follow `core.shlex`, which applies POSIX shell rules
  one line at a time: inside double quotes `\"` and `\\` are escapes (GNU
  treats the backslash literally), and a backslash at the end of a line does
  not join it to the next one.
- `-t` quotes the words the way `core.shlex.join` does (`'it'\''s'` where
  GNU writes `"it's"`; a newline inside single quotes rather than `$'\n'`).
- A command's output is collected and printed when it ends, as UTF-8 text,
  instead of going straight to the terminal.
- The runtime cannot redirect a child's standard input, so each command runs
  through `sh -c 'exec "$@" < /dev/null'` to get `/dev/null` as GNU xargs
  gives it.
- Whether the command can be run is asked of `test -x` (io.fs has no
  `stat()`), once, before the first run.
- A command that exits with a status from 129 to 254 is reported as killed
  by signal (status − 128): the runtime reports signals that way.
- `-s` above 2097152 is lowered to it without a warning.
- Not implemented: `-a`/`--arg-file`, `-E`/`-e`, `-i`, `-l`, `-x`, `-P`,
  `-o`, `-p`, `--show-limits`, `--process-slot-var`.
- `--version` prints one line: `xargs (loup-cmd-xargs) 0.1.0`.

## Layout

```text
source/main.loup              # entry point
source/appinfo.loup           # name, version, exit statuses 0, 1, 123-127
source/cli/args.loup          # getopt-style options, -d escapes, numbers
source/cli/usage.loup         # --help and --version text
source/cli/app.loup           # run(): parse, warnings, run_xargs, exit status
source/commands/input.loup    # splitting the input: core.shlex, -I lines, -0/-d
source/commands/xargs.loup    # build_plan(), running commands, statuses
tests/*_test.loup             # unit tests (make test)
tests/e2e.sh                  # end-to-end tests of build/xargs (make e2e)
specs/xargs/                  # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
