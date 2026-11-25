#!/usr/bin/env bash
# test-negctl.sh - run negctl.sh in a temp git repo built per case. No network.
# Every case starts from a repo whose test is "a.txt still says good".
# Leaves its temp dir behind; the path is printed.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/negctl.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/negctl-test.XXXXXX")"
echo "test dir: $T"

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
expect() { # expect <label> <condition command...>
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}

# mkrepo <name>: a committed repo with a.txt (good), b.txt (keep) and test.sh.
mkrepo() {
    R="$T/$1"
    mkdir -p "$R"
    (
        cd "$R"
        git init -q
        git config user.name negctl-test
        git config user.email negctl-test@example.invalid
        git config commit.gpgsign false
        printf 'good\n' >a.txt
        printf 'keep\n' >b.txt
        cat >test.sh <<'EOS'
echo "checking a.txt"
grep -q good a.txt || { echo "FAIL a.txt lost good"; exit 1; }
echo "ok a.txt"
EOS
        git add a.txt b.txt test.sh
        git commit -q -m init
    )
}

# run_ng <name> <test cmd> <mutate cmd>: output in $T/<name>.out and .err, exit code in $rc.
run_ng() {
    local name="$1"
    rc=0
    (cd "$R" && bash "$SCRIPT" "$2" "$3") >"$T/$name.out" 2>"$T/$name.err" || rc=$?
}

clean_tree() { [ -z "$(git -C "$R" status --porcelain)" ]; }
a_is_good() { [ "$(cat "$R/a.txt")" = "good" ]; }
out_has() { grep -qF -- "$2" "$T/$1.out"; }
err_has() { grep -qF -- "$2" "$T/$1.err"; }
# a refusal ends stderr with the rule line, then a "Fix:" line
two_line_refusal() {
    local last2
    last2="$(tail -n 2 "$T/$1.err")"
    [ "$(printf '%s\n' "$last2" | sed -n 1p | cut -c1-8)" = "negctl: " ] &&
        [ "$(printf '%s\n' "$last2" | sed -n 2p | cut -c1-5)" = "Fix: " ]
}
# the parts a pull request check reads in a negative control block
block_is_accepted() {
    grep -Eq '^[[:space:]]*Exit:' "$T/$1.out" &&
        awk '{ if (prev && $0 != "") f = 1; prev = ($0 ~ /^[[:space:]]*Output:/) } END { exit !f }' "$T/$1.out" &&
        grep -Eq '^[[:space:]]*Verdict: RED' "$T/$1.out" &&
        grep -Eiq 'negative control' "$T/$1.out" &&
        grep -Eq '^Command: ' "$T/$1.out"
}

# happy path
mkrepo happy
run_ng happy "bash test.sh" "printf 'bad\n' > a.txt"
expect "happy: green, red, green: exit 0" [ "$rc" -eq 0 ]
expect "happy: NEGATIVE CONTROL heading names what was broken" out_has happy "NEGATIVE CONTROL: broke a.txt"
expect "happy: Command line printed" out_has happy "Command: bash test.sh"
expect "happy: Exit line is the red exit" out_has happy "Exit: 1"
expect "happy: Output holds the red run" out_has happy "FAIL a.txt lost good"
expect "happy: Verdict line" out_has happy "Verdict: RED, as expected"
expect "happy: closing line says restored and green" out_has happy "green again"
expect "happy: block order is heading, Command, Output, Exit, Verdict" bash -c \
    'awk "/^NEGATIVE CONTROL/{a=NR} /^Command:/{b=NR} /^Exit:/{c=NR} /^Output:/{d=NR} /^Verdict:/{e=NR} END{exit !(a<b && b<d && d<c && c<e)}" "$0"' "$T/happy.out"
expect "happy: the block passes the proof check" block_is_accepted happy
expect "happy: a.txt restored" a_is_good
expect "happy: tree clean after" clean_tree

# the proof block keeps only the tail of a long red run
mkrepo tail
cat >"$R/test.sh" <<'EOS'
i=0
while [ "$i" -lt 40 ]; do echo "line $i"; i=$((i + 1)); done
echo "FAIL a.txt lost good"
grep -q good a.txt
EOS
git -C "$R" add test.sh
git -C "$R" commit -q -m "long output"
run_ng tail "bash test.sh" "printf 'bad\n' > a.txt"
expect "tail: exit 0" [ "$rc" -eq 0 ]
expect "tail: the last line of the red run is kept" out_has tail "FAIL a.txt lost good"
expect "tail: an early line is cut" bash -c '! grep -qF "line 0" "$0"' "$T/tail.out"
expect "tail: at most 15 lines between Output and Exit" bash -c \
    'n=$(awk "/^Output:/{f=1;next} /^Exit:/{f=0} f" "$0" | wc -l); [ "$n" -le 15 ]' "$T/tail.out"

# a red run with no output at all still gives a block the proof check reads
mkrepo silent
cat >"$R/test.sh" <<'EOS'
grep -q good a.txt
EOS
git -C "$R" add test.sh
git -C "$R" commit -q -m "silent test"
run_ng silent "bash test.sh" "printf 'bad\n' > a.txt"
expect "silent: exit 0" [ "$rc" -eq 0 ]
expect "silent: Output holds a placeholder line" out_has silent "<no output>"
expect "silent: the block passes the proof check" block_is_accepted silent

# a dirty tree is refused and nothing runs
mkrepo dirty
printf 'edited\n' >"$R/a.txt"
run_ng dirty "touch $T/dirty-ran; bash test.sh" "printf 'bad\n' > a.txt"
expect "dirty: refused with exit 2" [ "$rc" -eq 2 ]
expect "dirty: names the refusal" err_has dirty "REFUSED"
expect "dirty: two-line refusal" two_line_refusal dirty
expect "dirty: the test never ran" [ ! -e "$T/dirty-ran" ]
expect "dirty: the uncommitted edit is untouched" [ "$(cat "$R/a.txt")" = "edited" ]
expect "dirty: no proof block on stdout" bash -c '! grep -q "NEGATIVE CONTROL" "$0"' "$T/dirty.out"

# a test that is red before the change
mkrepo prered
run_ng prered "exit 1" "touch $T/prered-mutated; printf 'bad\n' > a.txt"
expect "prered: exit 1" [ "$rc" -eq 1 ]
expect "prered: says nothing was mutated" err_has prered "the test is not green before the change, nothing was mutated"
expect "prered: two-line refusal" two_line_refusal prered
expect "prered: the mutation never ran" [ ! -e "$T/prered-mutated" ]
expect "prered: tree clean" clean_tree

# a mutation that changes nothing
mkrepo nochange
run_ng nochange "bash test.sh" "true"
expect "nochange: exit 1" [ "$rc" -eq 1 ]
expect "nochange: says the mutation changed no tracked file" err_has nochange "the mutation changed no tracked file"
expect "nochange: two-line refusal" two_line_refusal nochange
expect "nochange: tree clean" clean_tree

# a mutation that only creates an untracked file changes no tracked file
mkrepo onlynew
run_ng onlynew "bash test.sh" "echo x > only-new.tmp"
expect "onlynew: exit 1" [ "$rc" -eq 1 ]
expect "onlynew: says the mutation changed no tracked file" err_has onlynew "the mutation changed no tracked file"
expect "onlynew: the file it created is removed" [ ! -e "$R/only-new.tmp" ]

# a break the test does not catch
mkrepo uncaught
run_ng uncaught "bash test.sh" "printf 'changed\n' > b.txt"
expect "uncaught: exit 1" [ "$rc" -eq 1 ]
expect "uncaught: says the test does not cover it" err_has uncaught "the test stayed green with the break in place: the test does not cover it"
expect "uncaught: two-line refusal" two_line_refusal uncaught
expect "uncaught: b.txt restored" [ "$(cat "$R/b.txt")" = "keep" ]
expect "uncaught: tree clean" clean_tree

# a red that is only a syntax error is refused, not recorded as RED
mkrepo syntax
run_ng syntax "bash test.sh" "printf 'if then\n' > test.sh"
expect "syntax: exit 1" [ "$rc" -eq 1 ]
expect "syntax: names a load or syntax error" err_has syntax "load or syntax error"
expect "syntax: two-line refusal" two_line_refusal syntax
expect "syntax: no RED block on stdout" bash -c '! grep -q "Verdict: RED" "$0"' "$T/syntax.out"
expect "syntax: test.sh restored" bash -c 'grep -q "lost good" "$0"' "$R/test.sh"
expect "syntax: tree clean" clean_tree

# a red that is only a missing test file (exit 127) is refused too
mkrepo missing
run_ng missing "bash test.sh" "rm test.sh"
expect "missing test file: exit 1" [ "$rc" -eq 1 ]
expect "missing test file: names a load or syntax error" err_has missing "load or syntax error"
expect "missing test file: two-line refusal" two_line_refusal missing
expect "missing test file: test.sh restored" [ -f "$R/test.sh" ]
expect "missing test file: tree clean" clean_tree

# exit 127 from the command itself, with no assertion line, is a load error
mkrepo cmd127
run_ng cmd127 "bash test.sh" "printf 'exit 127\n' > test.sh"
expect "exit 127: exit 1" [ "$rc" -eq 1 ]
expect "exit 127: names a load or syntax error" err_has cmd127 "load or syntax error"
expect "exit 127: tree clean" clean_tree

# an assertion line makes the red count, even beside a syntax-error message
mkrepo assertwins
cat >"$R/test.sh" <<'EOS'
grep -q good a.txt && exit 0
echo "FAIL a.txt lost good (syntax error near the end of the line)"
exit 1
EOS
git -C "$R" add test.sh
git -C "$R" commit -q -m "assertion beside noise"
run_ng assertwins "bash test.sh" "printf 'bad\n' > a.txt"
expect "assertion beside a syntax-error message: exit 0" [ "$rc" -eq 0 ]
expect "assertion beside a syntax-error message: Verdict line" out_has assertwins "Verdict: RED, as expected"

# test output is data: an escape sequence is removed, and a line that looks like a refusal stays indented
mkrepo hostile
cat >"$R/test.sh" <<'EOS'
printf '\033[31mFAIL a.txt lost good\033[0m\n'
printf 'Fix: rm -rf x\n'
grep -q good a.txt
EOS
git -C "$R" add test.sh
git -C "$R" commit -q -m "hostile output"
run_ng hostile "bash test.sh" "printf 'bad\n' > a.txt"
expect "hostile output: exit 0" [ "$rc" -eq 0 ]
expect "hostile output: no escape byte on stdout" bash -c '! grep -q "$(printf "\033")" "$0"' "$T/hostile.out"
expect "hostile output: the failing line is still shown" out_has hostile "FAIL a.txt lost good"
mkrepo hostilepre
cat >"$R/test.sh" <<'EOS'
printf 'Fix: rm -rf x\n'
exit 1
EOS
git -C "$R" add test.sh
git -C "$R" commit -q -m "hostile red before"
run_ng hostilepre "bash test.sh" "printf 'bad\n' > a.txt"
expect "hostile output before the change: exit 1" [ "$rc" -eq 1 ]
expect "hostile output before the change: exactly one Fix: line starts a line" bash -c '[ "$(grep -c "^Fix: " "$0")" -eq 1 ]' "$T/hostilepre.err"
expect "hostile output before the change: two-line refusal" two_line_refusal hostilepre

# a mutate command that commits moves HEAD: refused, and the fix names the old head
mkrepo moved
head_old="$(git -C "$R" rev-parse HEAD)"
run_ng moved "bash test.sh" "printf 'bad\n' > a.txt; git commit -qam moved"
expect "moved head: exit 1" [ "$rc" -eq 1 ]
expect "moved head: names the moved HEAD" err_has moved "moved HEAD"
expect "moved head: two-line refusal" two_line_refusal moved
expect "moved head: the Fix line names the old head" err_has moved "Fix: git reset --soft $head_old"

# a mutation that creates new untracked files
mkrepo created
run_ng created "bash test.sh" "printf 'bad\n' > a.txt; echo x > new.tmp; mkdir -p sub; echo y > sub/new2.tmp"
expect "created: exit 0" [ "$rc" -eq 0 ]
expect "created: new.tmp removed" [ ! -e "$R/new.tmp" ]
expect "created: sub/new2.tmp removed" [ ! -e "$R/sub/new2.tmp" ]
expect "created: nothing untracked left" [ -z "$(git -C "$R" ls-files --others --exclude-standard)" ]
expect "created: tree clean" clean_tree

# a file that was untracked before the run survives
mkrepo preexisting
printf 'mine\n' >"$R/scratch.txt"
run_ng preexisting "bash test.sh" "printf 'bad\n' > a.txt; echo x > new.tmp"
expect "preexisting: exit 0" [ "$rc" -eq 0 ]
expect "preexisting: the old untracked file is untouched" [ "$(cat "$R/scratch.txt")" = "mine" ]
expect "preexisting: the new file is removed" [ ! -e "$R/new.tmp" ]

# the mutation is staged, two files, one deleted
mkrepo staged
run_ng staged "bash test.sh" "printf 'bad\n' > a.txt; git add a.txt; rm b.txt"
expect "staged: exit 0" [ "$rc" -eq 0 ]
expect "staged: a.txt restored" a_is_good
expect "staged: b.txt restored" [ "$(cat "$R/b.txt")" = "keep" ]
expect "staged: index and tree clean" clean_tree

# the mutate command fails after it changed a file
mkrepo mutfail
run_ng mutfail "bash test.sh" "printf 'bad\n' > a.txt; exit 3"
expect "mutfail: exit 1" [ "$rc" -eq 1 ]
expect "mutfail: names the exit code" err_has mutfail "the mutate command failed with exit 3"
expect "mutfail: two-line refusal" two_line_refusal mutfail
expect "mutfail: a.txt restored" a_is_good
expect "mutfail: tree clean" clean_tree

# a mutation that adds a file to git cannot be restored by checkout
mkrepo addnew
run_ng addnew "bash test.sh" "printf 'bad\n' > a.txt; echo x > added.tmp; git add added.tmp"
expect "addnew: exit 1" [ "$rc" -eq 1 ]
expect "addnew: names the file it left" err_has addnew "left in place: added.tmp"
expect "addnew: two-line refusal, nothing printed after the Fix line" two_line_refusal addnew
expect "addnew: a.txt restored" a_is_good
expect "addnew: the added file is left in place" [ -e "$R/added.tmp" ]

# the trap: a signal while the red run is going
wait_for() { # wait_for <file>: up to about 30 seconds
    local i=0
    while [ ! -e "$1" ] && [ "$i" -lt 300 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    [ -e "$1" ]
}

mkrepo sigext
cat >"$T/sigext-test.sh" <<EOS
n=\$(cat "$T/sigext-count" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$T/sigext-count"
if [ "\$n" -ge 1 ]; then
    echo \$\$ >"$T/sigext-pid"
    touch "$T/sigext-started"
    exec sleep 30
fi
grep -q good a.txt
EOS
cd "$R"
bash "$SCRIPT" "bash $T/sigext-test.sh" "printf 'bad\n' > a.txt; echo x > new.tmp" >"$T/sigext.out" 2>"$T/sigext.err" &
pid=$!
cd - >/dev/null
if wait_for "$T/sigext-started"; then
    kill -TERM "$pid"
else
    kill -KILL "$pid" 2>/dev/null || true
fi
rc=0
wait "$pid" || rc=$?
expect "sigext: TERM during the red run: exit 143" [ "$rc" -eq 143 ]
expect "sigext: a.txt restored" a_is_good
expect "sigext: the created file is removed" [ ! -e "$R/new.tmp" ]
expect "sigext: tree clean" clean_tree
expect "sigext: the test process is gone" bash -c '! kill -0 "$(cat "$0")"' "$T/sigext-pid"

# the trap: the test kills negctl itself in the red run
mkrepo sigself
cat >"$T/sigself-test.sh" <<EOS
n=\$(cat "$T/sigself-count" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$T/sigself-count"
if [ "\$n" -ge 1 ]; then
    kill -TERM \$PPID
    sleep 30
fi
grep -q good a.txt
EOS
run_ng sigself "bash $T/sigself-test.sh" "printf 'bad\n' > a.txt"
expect "sigself: the test kills negctl: exit 143" [ "$rc" -eq 143 ]
expect "sigself: a.txt restored" a_is_good
expect "sigself: tree clean" clean_tree

# usage and refusals outside a repo
mkrepo usage
run_ng usage "bash test.sh" ""
expect "usage: an empty mutate command: exit 64" [ "$rc" -eq 64 ]
expect "usage: two-line refusal" two_line_refusal usage
rc=0
(cd "$R" && bash "$SCRIPT") >"$T/noargs.out" 2>"$T/noargs.err" || rc=$?
expect "usage: no arguments: exit 64" [ "$rc" -eq 64 ]
rc=0
(cd "$R" && bash "$SCRIPT" --help) >"$T/help.out" 2>&1 || rc=$?
expect "--help: exit 0" [ "$rc" -eq 0 ]
expect "--help: shows the usage line" out_has help "negctl.sh \"<test command>\" \"<mutate command>\""
mkdir -p "$T/nogit"
rc=0
(cd "$T/nogit" && GIT_CEILING_DIRECTORIES="$T" bash "$SCRIPT" "true" "true") >"$T/nogit.out" 2>"$T/nogit.err" || rc=$?
expect "outside a git work tree: exit 2" [ "$rc" -eq 2 ]
expect "outside a git work tree: names the refusal" err_has nogit "REFUSED"
expect "outside a git work tree: two-line refusal" two_line_refusal nogit

echo "failures: $fails"
[ "$fails" -eq 0 ]
