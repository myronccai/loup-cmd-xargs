# Requirements: xargs

## Introduction

`xargs` reads arguments from standard input and runs a command with them,
as many at a time as the options allow. This repository recreates the core
of GNU findutils `xargs` in Loup: blank-separated input with shell-style
quotes (split with `core.shlex`), delimiter-separated input (`-0`, `-d`),
grouping by count, lines, size and replacement string, `-t` and `-r`, and
GNU's exit statuses. Standard input can only be read whole in Loup 1.26.0
(roadmap constraint T2), so `-p` is out of scope.

## Requirements

### Requirement 1: Reading arguments

**User Story:** As a shell user, I want xargs to read the arguments I pipe
into it the way GNU xargs does so that existing pipelines work.

#### Acceptance Criteria

1. WHEN no -0, -d or -I is given, THE program SHALL split the input into
   arguments at blanks and newlines, honouring `'...'`, `"..."` and
   backslash escapes, one line at a time.
2. WHEN a quote is not closed on its line, THE program SHALL print
   `xargs: unmatched single quote; by default quotes are special to xargs
   unless you use the -0 option` (or `double`), run the command with the
   arguments read before it, and exit with status 1.
3. WHEN `-0` or `-d C` is given, THE program SHALL end arguments at NUL or
   at C only, with no quote processing, keeping empty arguments; a final
   delimiter SHALL not start another argument. `-d` SHALL accept one
   character or the escapes `\n \t \r \f \v \a \b \\ \xHH \NNN`.
4. WHEN `-I R` is given, THE program SHALL take each non-blank input line
   as one argument, without its leading blanks and quotes.

### Requirement 2: Building command lines

**User Story:** As a shell user, I want to control how many arguments each
command gets so that I can drive any command.

#### Acceptance Criteria

1. THE program SHALL run the command given after the options (default
   `echo`) with its initial arguments followed by input arguments.
2. WHEN `-n N` is given, THE program SHALL put at most N arguments on each
   command line.
3. WHEN `-L N` is given, THE program SHALL put the arguments of at most N
   non-blank input lines on each command line; a line ending in a blank SHALL
   continue on the next.
4. WHEN `-I R` is given, THE program SHALL run the command once per input
   line, with every R in the initial arguments (not the command name)
   replaced by the line.
5. THE program SHALL keep every command line within `-s` bytes (default
   131072), counting each word and its NUL; WHEN an argument cannot fit,
   THE program SHALL print `argument line too long`, run what it has and
   exit with status 1.
6. WHEN there are no input arguments, THE program SHALL run the command once
   without them, unless `-r` is given or `-I` is in effect.
7. WHEN `-n`, `-L` and `-I` are combined, THE program SHALL keep the later
   one and print GNU's warning, as GNU xargs does.

### Requirement 3: Running commands

**User Story:** As a shell user, I want to see and trust what xargs runs so
that I can use it in scripts.

#### Acceptance Criteria

1. WHEN `-t` is given, THE program SHALL print each command line, quoted for
   the shell, on standard error before running it.
2. THE program SHALL run each command line without a shell interpreting its
   words, with `/dev/null` as standard input, and pass on its standard output
   and standard error.
3. WHEN a command exits with 1–125, THE program SHALL go on and exit with
   status 123 at the end.
4. WHEN a command exits with 255, THE program SHALL print
   `xargs: CMD: exited with status 255; aborting` and exit with status 124.
5. WHEN a command is killed by a signal, THE program SHALL print
   `xargs: CMD: terminated by signal N` and exit with status 125.
6. WHEN the command cannot be run or is not found, THE program SHALL print
   `xargs: CMD: Permission denied` or `xargs: CMD: No such file or
   directory` and exit with status 126 or 127.

### Requirement 4: Command line

**User Story:** As a shell user, I want GNU xargs' option syntax and
diagnostics.

#### Acceptance Criteria

1. THE program SHALL accept short options bundled (`-0t`) and with attached
   or separate values (`-n2`, `-n 2`), long options with `=VALUE` or a
   separate value, and `--` before the command.
2. WHEN an option is unknown, lacks its value or has a bad number, THE
   program SHALL print GNU's message and `Try 'xargs --help' for more
   information.` on standard error and exit with status 1.
3. WHEN `--help` or `--version` is given, THE program SHALL print the help
   text or `xargs (loup-cmd-xargs) 0.1.0` and exit with status 0.
