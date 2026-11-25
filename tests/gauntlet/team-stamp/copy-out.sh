#!/usr/bin/env bash
# copy-out.sh -- the only code that reads anything out of a probe round on the host. Sourced by
# run.sh and by tier1.sh. Rule: nothing a probe wrote is read, written, listed or executed by a host
# process, except the fixed result names below, copied out of the checker container's output dir.
#
#   copy_results <outdir> <recorddir>
#     <outdir> was created by the host and written by the checker container; <recorddir> was created
#     by the host. A name is copied only when it is a regular file, not a symlink, and no larger than
#     RESULT_MAX_BYTES (default 5 MB); the copy is `cp -P`. The output dir itself must not be a
#     symlink. Everything else in <outdir> is ignored and counted in one log line. It sets the number
#     of names copied in COPIED and the number ignored in IGNORED.
#   scrub_dir <dir> <secret>
#     Scans every file under <dir> without -I (binary files too). A text file has the secret replaced
#     by <REDACTED-KEY>; a file that is not text and holds the secret is deleted. It then scans again
#     and returns 1 if the secret is still there.
RESULT_NAMES="verdict.txt checker-output.txt pr.json calls.jsonl clean-diff.patch transcript.jsonl"
RESULT_MAX_BYTES="${RESULT_MAX_BYTES:-5242880}"
COPIED=0 IGNORED=0

copy_results() {
    local out="$1" rec="$2" name n=0 total=0 size
    COPIED=0 IGNORED=0
    if [ ! -d "$out" ] || [ -L "$out" ]; then echo "copy-out: the output dir is missing or a symlink; nothing was read" >&2; return 1; fi
    if [ ! -d "$rec" ] || [ -L "$rec" ]; then echo "copy-out: the record dir is missing or a symlink; nothing was written" >&2; return 1; fi
    for name in $RESULT_NAMES; do
        if [ -f "$out/$name" ] && [ ! -L "$out/$name" ]; then
            size="$(wc -c <"$out/$name" 2>/dev/null | tr -d ' ')"
            if [ -n "$size" ] && [ "$size" -le "$RESULT_MAX_BYTES" ]; then
                cp -P "$out/$name" "$rec/$name" && n=$((n + 1))
            fi
        fi
    done
    total="$(find "$out" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
    COPIED="$n"
    IGNORED=$((total - n))
    echo "copy-out: copied $COPIED result file(s); ignored $IGNORED other entr$([ "$IGNORED" -eq 1 ] && echo y || echo ies) in the output dir"
    return 0
}

scrub_dir() {
    local dir="$1" secret="$2" f c
    [ -n "$secret" ] || return 0
    while IFS= read -r f; do
        [ -L "$f" ] && { rm -f -- "$f"; continue; }
        if grep -qI . "$f" 2>/dev/null; then
            c="$(cat "$f")"
            printf '%s\n' "${c//"$secret"/<REDACTED-KEY>}" >"$f"
        else
            echo "scrub: deleted a file that is not text and held the key: ${f##*/}" >&2
            rm -f -- "$f"
        fi
    done < <(grep -rlF -- "$secret" "$dir" 2>/dev/null || true)
    if grep -rqF -- "$secret" "$dir" 2>/dev/null; then return 1; fi
    return 0
}
