#!/usr/bin/env bash
# End-to-end tests: run the built binary with prepared standard input and
# compare its standard output (byte for byte), its standard error (where it
# matters) and its exit status with the expected ones.
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# check_file NAME STATUS EXPECTED_FILE [ARGS...]
# Runs BINARY ARGS... with standard input from the file named by $IN
# (default: /dev/null) and compares standard output with EXPECTED_FILE.
check_file() {
    local name=$1 want_status=$2 want_file=$3
    shift 3
    "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    local status=$?
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$TMP/out"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff <(od -c "$want_file") <(od -c "$TMP/out") | sed 's/^/    /' | head -20
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]
# As check_file, with the expected output given as a string. Bash strings
# cannot hold NUL bytes; use check_file for output that contains them.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    check_file "$name" "$want_status" "$TMP/want" "$@"
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]
# Runs BINARY ARGS... (standard input from $IN) and compares standard error
# and the exit status.
check_err() {
    local name=$1 want_status=$2 want_err=$3
    shift 3
    "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    local status=$?
    if [ "$status" -eq "$want_status" ] && [ "$(cat "$TMP/err")" = "$want_err" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        echo "    want stderr: $want_err"
        sed 's/^/    got stderr:  /' "$TMP/err" | head -5
    fi
}

# input FORMAT [ARGS...]: the next commands read printf FORMAT ARGS... .
input() {
    # shellcheck disable=SC2059
    printf "$@" > "$TMP/in"
    IN=$TMP/in
}

# Building command lines.
input 'a b\nc\n'
check "default echo"       0 $'a b c\n'
check "given command"      0 $'[a]\n[b]\n[c]\n'                printf '[%s]\n'
check "initial arguments"  0 $'x: a b c\n'                     echo x:
input ''
check "empty input"        0 $'\n'
check "-r"                 0 ''                                -r echo nothing
input '  \n\t\n'
check "blank input"        0 $'\n'
check "blank input -r"     0 ''                                -r
input 'a b c d e\n'
check "-n 2"               0 $'a b\nc d\ne\n'                  -n 2
check "-n2 attached"       0 $'a b\nc d\ne\n'                  -n2
check "--max-args"         0 $'a b c\nd e\n'                   --max-args=3
input 'a b\nc\nd e f\n'
check "-L 1"               0 $'a b\nc\nd e f\n'                -L 1
check "-L 2"               0 $'a b c\nd e f\n'                 -L 2
input 'a \n\nb\nc\n'
check "-L trailing blank"  0 $'a b\nc\n'                       -L 1
input 'a b c d\n'
check "-s 12"              0 $'a b c\nd\n'                     -s 12 echo
input '%s\n' '--x'
check "-- ends options"    0 $'x --x'                          -- echo -n x

# Quoting.
input '%s\n' "'a  b' \"c d\" e\\ f"
check "quotes"             0 $'[a  b]\n[c d]\n[e f]\n'         printf '[%s]\n'
input '%s\n' 'x"y z"w ""'
check "quotes in a word"   0 $'[xy zw]\n[]\n'                  printf '[%s]\n'
input '%s\n' 'a "b'
check "unmatched quote"    1 $'a\n'
check_err "unmatched message" 1 "xargs: unmatched double quote; by default quotes are special to xargs unless you use the -0 option"
input '%s\n' "'only"
check "nothing before it"  1 ''

# -I.
input '  a  b \n\n c\n'
check "-I"                 0 $'[a  b ]\n[c]\n'                 -I{} echo '[{}]'
input 'x\ny\n'
check "-I several"         0 $'x-x x\ny-y y\n'                 -I % echo %-% %
input '%s\n' "'a  b'  c"
check "-I quotes"          0 $'<a  b  c>\n'                    -I {} echo '<{}>'
check_err "-I not in command" 127 "xargs: {}x: No such file or directory" -I {} '{}x'
input ''
check "-I no input"        0 ''                                -I {} echo '<{}>'

# Delimiters.
input 'a:b::c'
check "-d"                 0 $'[a]\n[b]\n[]\n[c]\n'            -d : printf '[%s]\n'
input 'a b\nc\n'
check "-d newline"         0 $'[a b]\n[c]\n'                   -d '\n' printf '[%s]\n'
input 'a\tb'
check "-d tab"             0 $'[a]\n[b]\n'                     -d '\t' printf '[%s]\n'
input 'one 1\0two "2"\0'
check "-0"                 0 $'[one 1]\n[two "2"]\n'           -0 printf '[%s]\n'
check "--null"             0 $'[one 1]\n[two "2"]\n'           --null printf '[%s]\n'
input 'a b\0c\0'
printf 'a b\0c\0' > "$TMP/want0"
check_file "-0 output NUL" 0 "$TMP/want0"                      -0 printf '%s\0'

# -t.
input 'a  b\nc\n'
check_err "-t"             0 $'echo a b c'                     -t
check_err "-t quotes"      0 $'echo \'a  b\'\necho c'          -t -I{} echo '{}'

# Child output and input.
input 'a\n'
check "child stderr out"   0 $'out a\n'                        sh -c 'echo out "$1"; echo err >&2' sh
check_err "child stderr"   0 "err"                             sh -c 'echo out "$1"; echo err >&2' sh
check "child stdin is null" 0 $'done a\n'                      sh -c 'cat; echo done "$1"' sh

# Exit statuses.
input 'a\nb\n'
check "status 0"           0 $'a\nb\n'                         -n1 sh -c 'echo "$1"; exit 0' sh
check "status 1-125"       123 $'a\nb\n'                       -n1 sh -c 'echo "$1"; exit 3' sh
check "status 255 stops"   124 $'a\n'                          -n1 sh -c 'echo "$1"; exit 255' sh
check_err "255 message"    124 "xargs: sh: exited with status 255; aborting" -n1 sh -c 'exit 255' sh
check_err "signal"         125 "xargs: sh: terminated by signal 15" -n1 sh -c 'kill -TERM $$' sh
check_err "not found"      127 "xargs: no-such-command-zz: No such file or directory" no-such-command-zz
printf 'echo hi\n' > "$TMP/not-executable"
chmod 644 "$TMP/not-executable"
check_err "not executable" 126 "xargs: $TMP/not-executable: Permission denied" "$TMP/not-executable"
check_err "a directory"    126 "xargs: $TMP: Permission denied"  "$TMP"
check "false"              123 ''                              false

# Size errors.
input 'a b aaaaaaaaaaaaaa\n'
check "line too long"      1 $'a b\n'                          -s 12 echo
check_err "too long message" 1 "xargs: argument line too long"  -s 12 echo
input 'a\n'
check_err "command too long" 1 "xargs: cannot fit single argument within argument list size limit" -s 3 echo

# Options that cancel each other.
input 'a b\nc d\n'
check "-L after -n"        0 $'a b\nc d\n'                     -n 1 -L 1
check_err "-L after -n warns" 0 "xargs: warning: options --max-args and -L are mutually exclusive, ignoring previous --max-args value" -n 1 -L 1
check "-n after -L"        0 $'a\nb\nc\nd\n'                   -L 1 -n 1

# Command-line errors: message, usage hint, status 1.
IN=/dev/null
check_err "invalid option"    1 $'xargs: invalid option -- \'z\'\nTry \'xargs --help\' for more information.' -z
check_err "unknown long"      1 $'xargs: unrecognized option \'--bogus\'\nTry \'xargs --help\' for more information.' --bogus
check_err "missing value"     1 $'xargs: option requires an argument -- \'I\'\nTry \'xargs --help\' for more information.' -I
check_err "bad number"        1 $'xargs: invalid number "x" for -n option\nTry \'xargs --help\' for more information.' -n x
check_err "zero"              1 $'xargs: value 0 for -L option should be >= 1\nTry \'xargs --help\' for more information.' -L 0
check_err "bad delimiter"     1 "xargs: Invalid input delimiter specification ab: the delimiter must be either a single character or an escape sequence starting with \\." -d ab
check_err "bad escape"        1 "xargs: Invalid escape sequence \\q in input delimiter specification." -d '\q'
check "errors run nothing"    1 ''                             -n 0 echo x

# Help and version.
check "version"            0 $'xargs (loup-cmd-xargs) 0.1.0\n' --version
"$BIN" --help > "$TMP/help" 2>&1
if [ $? -eq 0 ] && head -1 "$TMP/help" | grep -q '^Usage: xargs '; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL: --help"
fi

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
