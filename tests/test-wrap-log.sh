#!/usr/bin/env bash
# test-wrap-log.sh -- the log and stage cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== log: the activity line, its path rules and its text rules ==="
# ===========================================================================
LOGHOME="$TMPD/home"; mkdir -p "$LOGHOME"
mkdir -p "$TMPD/outside"
KITROOT="$TMPD/kitroot"; mkdir -p "$KITROOT"
LOGFILE="$LOGHOME/ACTIVITY.md"
printf 'first old line\n' > "$LOGFILE"
printf 'old\n' > "$TMPD/outside/ACTIVITY.md"

set_log_key() { printf '[wrap]\nactivity_log = "%s"\n' "$1" > "$KITROOT/kit.toml"; }
wrap_log() { HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "$@"; }

set_log_key "$LOGFILE"
out="$(wrap_log "wrap: landed the session" 2>&1)"; rc=$?
chk "log exits 0 with the key set" "$rc"
chk "log prepends the dated line as line 1" \
  "$([ "$(head -1 "$LOGFILE")" = "$(date +%F) · wrap: landed the session" ]; echo $?)"
chk "log keeps the old first line" "$(grep -qx 'first old line' "$LOGFILE"; echo $?)"

wrap_log --date 2026-01-02 "wrap: backdated" >/dev/null 2>&1
chk "log --date overrides the prefix" \
  "$([ "$(head -1 "$LOGFILE")" = "2026-01-02 · wrap: backdated" ]; echo $?)"

DATE_BEFORE="$(cat "$LOGFILE")"
out="$(wrap_log --date "$(printf '2026-01-01\nFORGED')" "wrap: forged date" 2>&1)"; rc=$?
chk "log refuses a multi-line --date (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log names the --date format" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'wrap log: --date must be YYYY-MM-DD'; echo $?)"
chk "log wrote nothing on the forged date" "$([ "$DATE_BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"
out="$(wrap_log --date 2026-13-45 "wrap: impossible date" 2>&1)"; rc=$?
chk "log refuses an out-of-range --date (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log wrote nothing on the out-of-range date" "$([ "$DATE_BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"

BEFORE="$(cat "$LOGFILE")"
# The dash is assembled from its bytes: a literal one in this file would violate the
# repo-wide formatting rule the verb under test enforces.
EM="$(printf '\xe2\x80\x94')"
out="$(wrap_log "wrap: an em dash ${EM} here" 2>&1)"; rc=$?
chk "log refuses an em dash (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log wrote nothing on the em dash" "$([ "$BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"

out="$(wrap_log "$(printf 'wrap: two\nlines')" 2>&1)"; rc=$?
chk "log refuses a newline (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log wrote nothing on the newline" "$([ "$BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"

LONG="wrap: $(head -c 320 < /dev/zero | tr '\0' 'x')"
out="$(wrap_log "$LONG" 2>&1)"; rc=$?
chk "log writes a 320-char text" "$rc"
chk "log warns over the 300-char budget" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'over the 300-char routine budget'; echo $?)"

set_log_key "$LOGHOME/no-such-file.md"
out="$(wrap_log "wrap: missing target" 2>&1)"; rc=$?
chk "log exits 1 on a missing file" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log names the resolved path" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'no-such-file.md'; echo $?)"

set_log_key "$TMPD/outside/ACTIVITY.md"
out="$(wrap_log "wrap: outside home" 2>&1)"; rc=$?
chk "log exits 1 on an absolute path outside HOME" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log left the outside file untouched" "$([ "$(cat "$TMPD/outside/ACTIVITY.md")" = "old" ]; echo $?)"

set_log_key "$LOGHOME/../outside/ACTIVITY.md"
out="$(wrap_log "wrap: dotdot" 2>&1)"; rc=$?
chk "log exits 1 on a .. path that escapes HOME" "$([ "$rc" -eq 1 ]; echo $?)"

set_log_key "relative/ACTIVITY.md"
out="$(wrap_log "wrap: relative" 2>&1)"; rc=$?
chk "log exits 1 on a relative path" "$([ "$rc" -eq 1 ]; echo $?)"

mkdir -p "$TMPD/projrepo"
printf '[wrap]\nactivity_log = "%s"\n' "$LOGHOME/PROJECT.md" > "$TMPD/projrepo/.kit.toml"
printf 'untouched\n' > "$LOGHOME/PROJECT.md"
printf '[wrap]\n' > "$KITROOT/kit.toml"
out="$(cd "$TMPD/projrepo" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: project toml" 2>&1)"; rc=$?
chk "log ignores a project .kit.toml key (exit 0)" "$rc"
chk "log says the line did not land" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'no wrap.activity_log key in the kit-root kit.toml; line not written'; echo $?)"
chk "log still prints the line it would have written" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q ' · wrap: project toml'; echo $?)"
chk "log left the project-named file untouched" "$([ "$(cat "$LOGHOME/PROJECT.md")" = "untouched" ]; echo $?)"

# The operator config overlay (SPEC-248) owns this key too: it is as trusted as the kit root,
# so its value overrides a kit-root value for the same key.
OPCONF="$TMPD/opconfig"; mkdir -p "$OPCONF"
printf 'operator base\n' > "$LOGHOME/OPERATOR.md"
printf 'kit-root base\n' > "$LOGHOME/KITROOT.md"
set_log_key "$LOGHOME/KITROOT.md"
printf '[wrap]\nactivity_log = "%s"\n' "$LOGHOME/OPERATOR.md" > "$OPCONF/kit.toml"
out="$(HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" KIT_CONFIG_OPERATOR="$OPCONF" \
  "$WRAP" log "wrap: operator toml" 2>&1)"; rc=$?
chk "log exits 0 with the operator kit.toml key set" "$rc"
chk "log prepends to the operator-named file" \
  "$([ "$(head -1 "$LOGHOME/OPERATOR.md")" = "$(date +%F) · wrap: operator toml" ]; echo $?)"
chk "log left the kit-root-named file untouched (operator wins)" \
  "$([ "$(cat "$LOGHOME/KITROOT.md")" = "kit-root base" ]; echo $?)"

# The configured log sits inside a repo's main checkout; a session working in a worktree of
# that repo gets the same repo-relative file inside its worktree, so the line is committable.
LOGREPO="$LOGHOME/logrepo"
git init -q "$LOGREPO" && git -C "$LOGREPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$LOGREPO/_meta" && printf 'main copy
' > "$LOGREPO/_meta/LOG.md"
git -C "$LOGREPO" add _meta/LOG.md && git -C "$LOGREPO" -c user.name=t -c user.email=t@t commit -q -m log
git -C "$LOGREPO" worktree add -q -b side "$LOGHOME/logrepo-wt"
set_log_key "$LOGREPO/_meta/LOG.md"
( cd "$LOGHOME/logrepo-wt" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: from a worktree" >/dev/null 2>&1 )
chk "log from a worktree prepends to the worktree's copy" \
  "$([ "$(head -1 "$LOGHOME/logrepo-wt/_meta/LOG.md")" = "$(date +%F) · wrap: from a worktree" ]; echo $?)"
chk "log from a worktree leaves the main checkout's copy untouched" \
  "$([ "$(cat "$LOGREPO/_meta/LOG.md")" = "main copy" ]; echo $?)"
( cd "$LOGHOME" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: from outside" >/dev/null 2>&1 )
chk "log from outside the repo prepends to the configured file itself" \
  "$([ "$(head -1 "$LOGREPO/_meta/LOG.md")" = "$(date +%F) · wrap: from outside" ]; echo $?)"

# ===========================================================================
echo "=== log/stage: the default-branch warning, written but not to be committed here ==="
# ===========================================================================
# A commit on the default branch cannot be pushed through a PR, so the verb writes the file
# and says the line belongs to the next feature PR. The write itself is never refused.
DBREPO="$LOGHOME/dbrepo"
git init -q "$DBREPO"
git -C "$DBREPO" symbolic-ref HEAD refs/heads/main
git -C "$DBREPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$DBREPO/_meta" && printf 'seed\n' > "$DBREPO/_meta/LOG.md"
git -C "$DBREPO" add _meta/LOG.md && git -C "$DBREPO" -c user.name=t -c user.email=t@t commit -q -m log
set_log_key "$DBREPO/_meta/LOG.md"

out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: on main" 2>&1)"
chk_has "log on the default branch warns" "$out" "on the default branch (main)"
chk_has "log names the next feature PR as the carrier" "$out" "next feature PR"
chk "log on the default branch still wrote the line" \
  "$([ "$(head -1 "$DBREPO/_meta/LOG.md")" = "$(date +%F) · wrap: on main" ]; echo $?)"

git -C "$DBREPO" checkout -q -b feat/log-guard
out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: on a branch" 2>&1)"
chk_no "log on a feature branch does not warn" "$out" "default branch"
chk "log on a feature branch still wrote the line" \
  "$([ "$(head -1 "$DBREPO/_meta/LOG.md")" = "$(date +%F) · wrap: on a branch" ]; echo $?)"

# origin/HEAD, not the local branch name, decides which branch is the default one: a repo whose
# remote default is `master` gets no warning for a session sitting on a local `main`.
git init -q --bare "$LOGHOME/dbremote.git"
git -C "$DBREPO" remote add origin "$LOGHOME/dbremote.git"
git -C "$DBREPO" push -q origin "HEAD:refs/heads/master"
git -C "$DBREPO" fetch -q origin
git -C "$DBREPO" checkout -q main
out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: local main, remote master" 2>&1)"
chk_no "log: a local main is not the default when origin says master" "$out" "default branch"
git -C "$DBREPO" checkout -q -B master
out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: on remote master" 2>&1)"
chk_has "log: the remote's own default branch warns" "$out" "on the default branch (master)"

STAGEDB="$TMPD/stage-defaultbranch"
git init -q "$STAGEDB"
git -C "$STAGEDB" symbolic-ref HEAD refs/heads/main
git -C "$STAGEDB" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
out="$(cd "$STAGEDB" && "$WRAP" stage "Guarded Title" "the intent" "the home" 2>&1)"
chk_has "stage on the default branch warns" "$out" "on the default branch (main)"
chk "stage on the default branch still wrote the block" \
  "$(grep -q '## \[staged\] Guarded Title' "$STAGEDB/_meta/backlog-staging.md"; echo $?)"
git -C "$STAGEDB" checkout -q -b feat/stage-guard
out="$(cd "$STAGEDB" && "$WRAP" stage "Branch Title" "i" "h" 2>&1)"
chk_no "stage on a feature branch does not warn" "$out" "default branch"

# ===========================================================================
echo "=== log: the --- anchor lands the entry below the header, not above it ==="
# ===========================================================================
ANCHFILE="$LOGHOME/ANCHOR.md"
printf '# LAB_LOG\n\nChronological log. Newest first.\n\n---\n\n2026-01-01 · old entry\n' > "$ANCHFILE"
set_log_key "$ANCHFILE"
wrap_log "wrap: anchored entry" >/dev/null 2>&1
chk "log: the title stays line 1, not pushed down" \
  "$([ "$(sed -n '1p' "$ANCHFILE")" = "# LAB_LOG" ]; echo $?)"
chk "log: the new entry lands right after the --- and its blank line" \
  "$([ "$(sed -n '7p' "$ANCHFILE")" = "$(date +%F) · wrap: anchored entry" ]; echo $?)"
chk "log: the previously-newest entry is now second" \
  "$([ "$(sed -n '8p' "$ANCHFILE")" = "2026-01-01 · old entry" ]; echo $?)"

FMFILE="$LOGHOME/FRONTMATTER.md"
printf -- '---\nkind: log\n---\n2026-01-01 · old entry\n' > "$FMFILE"
set_log_key "$FMFILE"
wrap_log "wrap: past the frontmatter" >/dev/null 2>&1
chk "log: frontmatter's opening --- is not mistaken for the anchor" \
  "$([ "$(sed -n '1p' "$FMFILE")" = "---" ]; echo $?)"
chk "log: the entry lands after the frontmatter's closing ---, not inside it" \
  "$([ "$(sed -n '4p' "$FMFILE")" = "$(date +%F) · wrap: past the frontmatter" ]; echo $?)"
chk "log: the frontmatter body is untouched" \
  "$([ "$(sed -n '2p' "$FMFILE")" = "kind: log" ]; echo $?)"

NOANCHFILE="$LOGHOME/NOANCHOR.md"
printf 'just a plain log, no header at all\n' > "$NOANCHFILE"
set_log_key "$NOANCHFILE"
wrap_log "wrap: no anchor falls back to prepend" >/dev/null 2>&1
chk "log: no --- anchor falls back to the old prepend-at-line-1 behavior" \
  "$([ "$(sed -n '1p' "$NOANCHFILE")" = "$(date +%F) · wrap: no anchor falls back to prepend" ]; echo $?)"

HDRONLYFILE="$LOGHOME/HDRONLY.md"
printf '# LAB_LOG\n\nChronological log.\n\n---\n' > "$HDRONLYFILE"
set_log_key "$HDRONLYFILE"
wrap_log "wrap: first entry in a header-only file" >/dev/null 2>&1
chk "log: a header-only file (no entries yet) still gets the entry after ---" \
  "$([ "$(sed -n '6p' "$HDRONLYFILE")" = "$(date +%F) · wrap: first entry in a header-only file" ]; echo $?)"

EMPTYFILE="$LOGHOME/EMPTY.md"
: > "$EMPTYFILE"
set_log_key "$EMPTYFILE"
wrap_log "wrap: an empty file still works" >/dev/null 2>&1
chk "log: an empty file gets the entry as line 1" \
  "$([ "$(sed -n '1p' "$EMPTYFILE")" = "$(date +%F) · wrap: an empty file still works" ]; echo $?)"

# ===========================================================================
echo "=== knowledge-root: the key, the HOME fence, and the repo argument ==="
# ===========================================================================
KRHOME="$TMPD/kr-home"; mkdir -p "$KRHOME/root-ok"
KROUTSIDE="$TMPD/kr-outside"; mkdir -p "$KROUTSIDE"
KRKITROOT="$TMPD/kr-kitroot"; mkdir -p "$KRKITROOT"
KRREPO="$TMPD/kr-repo"; mkdir -p "$KRREPO"
git -C "$KRREPO" init -q; gitc "$KRREPO"

set_kr_key() { printf '[knowledge]\nroot = "%s"\n' "$1" > "$KRKITROOT/kit.toml"; }
kr() { HOME="$KRHOME" KIT_CONFIG_ROOT="$KRKITROOT" "$WRAP" knowledge-root "$@"; }

printf '[knowledge]\n' > "$KRKITROOT/kit.toml"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: key empty exits 0" "$rc"
chk_has "knowledge-root: key empty prints the repo-local fallback" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: key empty creates nothing" "$([ ! -e "$KRREPO/.claude/memory" ]; echo $?)"

set_kr_key "$KRHOME/root-ok"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: filled, under HOME, existing, exits 0" "$rc"
chk_has "knowledge-root: prints <root>/projects/<basename>" "$out" "root-ok/projects/kr-repo"
chk "knowledge-root: creates <root>/projects/<basename>" "$([ -d "$KRHOME/root-ok/projects/kr-repo" ]; echo $?)"

set_kr_key "$KRHOME/missing-root"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: filled but missing still exits 0 (fallback, not an error)" "$rc"
chk_has "knowledge-root: filled but missing falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk_has "knowledge-root: filled but missing names the reason on stderr" "$out" "knowledge-root:"
chk "knowledge-root: filled but missing creates nothing under the still-missing root" \
  "$([ ! -e "$KRHOME/missing-root" ]; echo $?)"

set_kr_key "$KROUTSIDE"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: filled but outside HOME falls back, exit 0" "$rc"
chk_has "knowledge-root: outside HOME falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: outside HOME creates nothing there" "$([ ! -e "$KROUTSIDE/projects" ]; echo $?)"

ln -s "$KROUTSIDE" "$KRHOME/link-outside"
set_kr_key "$KRHOME/link-outside"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: a symlink resolving outside HOME falls back, exit 0" "$rc"
chk_has "knowledge-root: symlink-outside falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: symlink-outside creates nothing under the real target" \
  "$([ ! -e "$KROUTSIDE/projects" ]; echo $?)"

# The fence resolves `<root>` only. `mkdir -p` walks straight through a symlink at
# `<root>/projects`, so the created directory lands wherever that symlink points.
KRESC="$TMPD/kr-escape"; mkdir -p "$KRESC"
mkdir -p "$KRHOME/root-esc"; ln -s "$KRESC" "$KRHOME/root-esc/projects"
set_kr_key "$KRHOME/root-esc"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: a symlinked projects dir falls back, exit 0" "$rc"
chk_has "knowledge-root: symlinked projects falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: creates nothing under the symlink target" \
  "$([ ! -e "$KRESC/kr-repo" ]; echo $?)"

# `config seams` calls a root equal to $HOME `filled`, so the consumer must accept it too:
# an advisor that disagrees with the thing it advises on is the bug this closes.
KRHOME_REAL="$(cd "$KRHOME" && pwd -P)"
set_kr_key "$KRHOME"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: a root equal to HOME itself exits 0" "$rc"
chk_has "knowledge-root: HOME-as-root prints <HOME>/projects/<basename>" \
  "$out" "$KRHOME_REAL/projects/kr-repo"
chk "knowledge-root: HOME-as-root creates the directory" \
  "$([ -d "$KRHOME_REAL/projects/kr-repo" ]; echo $?)"

out="$(kr 2>&1)"; rc=$?
chk "knowledge-root: missing repo argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

out="$(kr "$KRREPO/no-such-subdir/.." 2>&1)"; rc=$?
chk "knowledge-root: repo arg ending in /.. exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

out="$(kr / 2>&1)"; rc=$?
chk "knowledge-root: repo arg resolving to / exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

# The only write this verb does is `mkdir -p` under `<root>/projects/<base>`, which sits
# OUTSIDE `<repo>` entirely -- so a `<repo>` with no `.git` at all must not block it. The
# old `_write_guard "$repo_real"` call shelled out to `git -C "$repo" rev-parse`, which
# fails on a non-git dir and printed the misleading "index.lock held by another writer".
KRNONGIT="$TMPD/kr-nongit-repo"; mkdir -p "$KRNONGIT"
set_kr_key "$KRHOME/root-ok"
out="$(kr "$KRNONGIT" 2>&1)"; rc=$?
chk "knowledge-root: non-git repo dir, filled+existing root, exits 0" "$rc"
chk_has "knowledge-root: non-git repo prints <root>/projects/<basename>" \
  "$out" "root-ok/projects/kr-nongit-repo"
chk "knowledge-root: non-git repo creates <root>/projects/<basename>" \
  "$([ -d "$KRHOME/root-ok/projects/kr-nongit-repo" ]; echo $?)"
chk_no "knowledge-root: non-git repo never prints the index.lock message" \
  "$out" "index.lock held by another writer"

# ===========================================================================
echo "=== stage: default paths, dedupe, the fences, and the worktree copy ==="
# ===========================================================================
STAGEHOME="$TMPD/stage-home"; mkdir -p "$STAGEHOME"
mk_stage_repo() { # mk_stage_repo <name> -- prints the new repo's path
  local d="$TMPD/stage-$1"
  mkdir -p "$d"; git -C "$d" init -q; gitc "$d"
  git -C "$d" commit -q --allow-empty -m init
  printf '%s' "$d"
}

R1="$(mk_stage_repo one)"
out="$(cd "$R1" && "$WRAP" stage "My First Title" "the intent" "the home" 2>&1)"; rc=$?
chk "stage: default paths exits 0" "$rc"
chk "stage: creates _meta/backlog-staging.md" "$([ -f "$R1/_meta/backlog-staging.md" ]; echo $?)"
chk_has "stage: appends the rendered block" "$(cat "$R1/_meta/backlog-staging.md")" "## [staged] My First Title"

out="$(cd "$R1" && "$WRAP" stage "my   FIRST title!!" "x" "y" 2>&1)"; rc=$?
chk "stage: a dup differing in case/spacing/punctuation exits 0" "$rc"
chk_has "stage: the dup prints already staged" "$out" "already staged"
DUP_COUNT="$(grep -c '^## \[staged\]' "$R1/_meta/backlog-staging.md")"
chk "stage: the dup wrote no second block" "$([ "$DUP_COUNT" -eq 1 ]; echo $?)"

R2="$(mk_stage_repo two)"
mkdir -p "$STAGEHOME/override-home"
: > "$STAGEHOME/override-home/staging.md"
out="$(cd "$R2" && BACKLOG_STAGE_STAGING="$STAGEHOME/override-home/staging.md" HOME="$STAGEHOME" \
  "$WRAP" stage "Override Path Title" "i" "h" 2>&1)"; rc=$?
chk "stage: BACKLOG_STAGE_STAGING under HOME honoured, exit 0" "$rc"
chk_has "stage: writes the overridden path" \
  "$(cat "$STAGEHOME/override-home/staging.md")" "## [staged] Override Path Title"
chk "stage: never touches the repo default path" "$([ ! -e "$R2/_meta/backlog-staging.md" ]; echo $?)"

# The override reaches wrap through the environment, which a repo `.envrc` writes. An absent
# leaf under HOME is exactly the shape that would let it seed a staging block into an agent
# instruction file, so the override may only append to a file that already exists.
R2B="$(mk_stage_repo two-b)"
ABSENT="$STAGEHOME/override-home/absent-instructions.md"
out="$(cd "$R2B" && BACKLOG_STAGE_STAGING="$ABSENT" HOME="$STAGEHOME" \
  "$WRAP" stage "Injected Row" "i" "h" 2>&1)"; rc=$?
chk "stage: an env-override at an absent file refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names the existing-regular-file rule" "$out" "not an existing regular file"
chk "stage: the absent override path is still absent" "$([ ! -e "$ABSENT" ]; echo $?)"

R3="$(mk_stage_repo three)"
mkdir -p "$R3/_meta"; ln -s /etc/hosts "$R3/_meta/backlog-staging.md"
out="$(cd "$R3" && "$WRAP" stage "T" "i" "h" 2>&1)"; rc=$?
chk "stage: a symlinked target refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names the reason on stderr" "$out" "wrap stage:"
chk "stage: the symlink itself is left alone" "$([ -L "$R3/_meta/backlog-staging.md" ]; echo $?)"

R4="$(mk_stage_repo four)"
mkdir -p "$STAGEHOME/elsewhere" "$STAGEHOME/some-other-home"
out="$(cd "$R4" && BACKLOG_STAGE_STAGING="$STAGEHOME/elsewhere/staging.md" HOME="$STAGEHOME/some-other-home" \
  "$WRAP" stage "T" "i" "h" 2>&1)"; rc=$?
chk "stage: outside the repo and outside HOME refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk "stage: nothing written outside" "$([ ! -e "$STAGEHOME/elsewhere/staging.md" ]; echo $?)"

out="$("$WRAP" stage "T" "i" "h" --repo "$TMPD/not-a-repo" 2>&1)"; rc=$?
chk "stage: a non-git --repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

R5="$(mk_stage_repo five)"
mkdir -p "$R5/_meta"; : > "$R5/_meta/backlog-staging.md"; chmod 400 "$R5/_meta/backlog-staging.md"
out="$(cd "$R5" && "$WRAP" stage "T" "i" "h" 2>&1)"; rc=$?
chk "stage: an unwritable target relays FAILED, exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "stage: relays the FAILED line" "$out" "FAILED"
chmod 644 "$R5/_meta/backlog-staging.md"

R6MAIN="$TMPD/stage-six"
git init -q "$R6MAIN" && git -C "$R6MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R6MAIN/_meta"
printf '# Backlog staging\n\n' > "$R6MAIN/_meta/backlog-staging.md"
git -C "$R6MAIN" add _meta/backlog-staging.md
git -C "$R6MAIN" -c user.name=t -c user.email=t@t commit -q -m stage
git -C "$R6MAIN" worktree add -q -b stage-side "$TMPD/stage-six-wt"
out="$(cd "$TMPD/stage-six-wt" && "$WRAP" stage --repo "$R6MAIN" "From The Worktree" "i" "h" 2>&1)"; rc=$?
chk "stage: run from a worktree exits 0" "$rc"
chk_has "stage: writes the worktree's own copy" \
  "$(cat "$TMPD/stage-six-wt/_meta/backlog-staging.md")" "## [staged] From The Worktree"
chk_no "stage: the main checkout's copy is left alone" \
  "$(cat "$R6MAIN/_meta/backlog-staging.md")" "## [staged] From The Worktree"

# The checks above run on the path BEFORE `_worktree_copy` swaps in the current worktree's own
# copy. A symlink at that copy redirects the append anywhere, so the refusal runs again after.
WTHOME="$TMPD/wt-home"; mkdir -p "$WTHOME"
CANARY="$TMPD/wt-canary.md"; printf 'canary untouched\n' > "$CANARY"
R7MAIN="$WTHOME/stage-seven"
git init -q "$R7MAIN" && git -C "$R7MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R7MAIN/_meta"
printf '# Backlog staging\n\n' > "$R7MAIN/_meta/backlog-staging.md"
git -C "$R7MAIN" add _meta/backlog-staging.md
git -C "$R7MAIN" -c user.name=t -c user.email=t@t commit -q -m stage
git -C "$R7MAIN" worktree add -q -b stage-evil "$WTHOME/stage-seven-wt"
rm -f "$WTHOME/stage-seven-wt/_meta/backlog-staging.md"
ln -s "$CANARY" "$WTHOME/stage-seven-wt/_meta/backlog-staging.md"
CANARY_BEFORE="$(shasum -a 256 "$CANARY" | cut -d' ' -f1)"
out="$(cd "$WTHOME/stage-seven-wt" && HOME="$WTHOME" "$WRAP" stage --repo "$R7MAIN" "Redirected Row" "i" "h" 2>&1)"; rc=$?
chk "stage: a symlinked worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names the symlink on stderr" "$out" "is a symlink"
chk "stage: the canary outside HOME is byte-identical" \
  "$([ "$CANARY_BEFORE" = "$(shasum -a 256 "$CANARY" | cut -d' ' -f1)" ]; echo $?)"

# Same shape for `wrap log`: the configured activity_log is fenced, its worktree copy is not.
LOGWTKIT="$TMPD/wt-kitroot"; mkdir -p "$LOGWTKIT"
LOGCANARY="$TMPD/wt-log-canary.md"; printf 'log canary untouched\n' > "$LOGCANARY"
R8MAIN="$WTHOME/log-eight"
git init -q "$R8MAIN" && git -C "$R8MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R8MAIN/_meta"
printf 'main copy\n' > "$R8MAIN/_meta/LOG.md"
git -C "$R8MAIN" add _meta/LOG.md
git -C "$R8MAIN" -c user.name=t -c user.email=t@t commit -q -m log
git -C "$R8MAIN" worktree add -q -b log-evil "$WTHOME/log-eight-wt"
rm -f "$WTHOME/log-eight-wt/_meta/LOG.md"
ln -s "$LOGCANARY" "$WTHOME/log-eight-wt/_meta/LOG.md"
printf '[wrap]\nactivity_log = "%s"\n' "$R8MAIN/_meta/LOG.md" > "$LOGWTKIT/kit.toml"
LOGCANARY_BEFORE="$(shasum -a 256 "$LOGCANARY" | cut -d' ' -f1)"
out="$(cd "$WTHOME/log-eight-wt" && HOME="$WTHOME" KIT_CONFIG_ROOT="$LOGWTKIT" "$WRAP" log "wrap: redirected" 2>&1)"; rc=$?
chk "log: a symlinked worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "log: names the symlink on stderr" "$out" "is a symlink"
chk "log: the canary outside HOME is byte-identical" \
  "$([ "$LOGCANARY_BEFORE" = "$(shasum -a 256 "$LOGCANARY" | cut -d' ' -f1)" ]; echo $?)"

# A symlink at a PARENT directory of the worktree copy escapes a leaf-only refusal and a
# prefix fence run on the unresolved string: `wt/_meta` pointing at a directory outside HOME
# still leaves `wt/_meta/<file>` looking like a plain file under the worktree. Both verbs must
# resolve the copied path before they fence it.
PDHOME="$TMPD/pd-home"; mkdir -p "$PDHOME"
PDOUT="$TMPD/pd-outside/_meta"; mkdir -p "$PDOUT"
printf 'staging canary untouched\n' > "$PDOUT/backlog-staging.md"
printf 'log canary untouched\n' > "$PDOUT/LOG.md"
R9MAIN="$PDHOME/pd-main"
git init -q "$R9MAIN" && git -C "$R9MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R9MAIN/_meta"
printf '# Backlog staging\n\n' > "$R9MAIN/_meta/backlog-staging.md"
printf 'main copy\n' > "$R9MAIN/_meta/LOG.md"
git -C "$R9MAIN" add _meta
git -C "$R9MAIN" -c user.name=t -c user.email=t@t commit -q -m meta
git -C "$R9MAIN" worktree add -q -b pd-side "$PDHOME/pd-wt"
rm -rf "$PDHOME/pd-wt/_meta"
ln -s "$TMPD/pd-outside/_meta" "$PDHOME/pd-wt/_meta"
git -C "$PDHOME/pd-wt" add _meta 2>/dev/null
git -C "$PDHOME/pd-wt" -c user.name=t -c user.email=t@t commit -q -m symlinked-meta 2>/dev/null
PD_STAGE_BEFORE="$(shasum -a 256 "$PDOUT/backlog-staging.md" | cut -d' ' -f1)"
PD_LOG_BEFORE="$(shasum -a 256 "$PDOUT/LOG.md" | cut -d' ' -f1)"

out="$(cd "$PDHOME/pd-wt" && HOME="$PDHOME" "$WRAP" stage --repo "$R9MAIN" "Parent Symlink Row" "i" "h" 2>&1)"; rc=$?
chk "stage: a parent-dir symlink on the worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names a reason on stderr" "$out" "wrap stage:"
chk "stage: the staging canary outside HOME is byte-identical" \
  "$([ "$PD_STAGE_BEFORE" = "$(shasum -a 256 "$PDOUT/backlog-staging.md" | cut -d' ' -f1)" ]; echo $?)"

PDKIT="$TMPD/pd-kitroot"; mkdir -p "$PDKIT"
printf '[wrap]\nactivity_log = "%s"\n' "$R9MAIN/_meta/LOG.md" > "$PDKIT/kit.toml"
out="$(cd "$PDHOME/pd-wt" && HOME="$PDHOME" KIT_CONFIG_ROOT="$PDKIT" "$WRAP" log "wrap: parent symlink" 2>&1)"; rc=$?
chk "log: a parent-dir symlink on the worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "log: names a reason on stderr" "$out" "wrap log:"
chk "log: the log canary outside HOME is byte-identical" \
  "$([ "$PD_LOG_BEFORE" = "$(shasum -a 256 "$PDOUT/LOG.md" | cut -d' ' -f1)" ]; echo $?)"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-log: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-log: all $PASS passed"
