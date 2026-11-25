#!/usr/bin/env bash
# test-sync-characterize.sh -- the golden capture of every board and sync entry point.
#
# It records what the code does, byte for byte, over fixtures and PATH stubs, and diffs it against
# tests/fixtures/sync-characterize/golden.txt. A refactor of lib/board and lib/sync is a pure move
# plus an indirection when this suite stays green; the only diffs allowed are the rows listed in
# tests/fixtures/sync-characterize/deltas.txt (one `<section><TAB><tag>` row per hunk, tag from a
# closed list). The baselines of the sync and board suites say the same tests still pass; this
# suite says the same bytes still come out.
#
# Sections (each headed `## <name>` in the golden):
#   1-sync-argv      `board sync` argv: config matrix -> the flags the engine receives
#   2-engine-flags   `backlog_sync.py --help`, reduced to sorted `flag<TAB>help` lines
#   7-help-errors    `board help`, an unknown verb, the engine with no --apps and with a bad app,
#                    `board sweep` with an unknown flag
#
# Safety. Nothing here reaches a real store or service. Every entry point runs under `env -i` in a
# scratch HOME with PATH stubs for ssh, osascript, gh, ntn, hermes, curl, op and secret-cache-read
# (recorders that print canned data), a scratch data root and config roots, and no token in the
# environment. A transport guard fails the run when a stub is bypassed: a Python sitecustomize makes
# subprocess raise for any of those programs that does not resolve into the stub directory and makes
# a non-loopback socket raise; a PATH check proves each program resolves into the stub directory.
#
# Run:     bash tests/test-sync-characterize.sh
# Update:  CHARACTERIZE_UPDATE=1 bash tests/test-sync-characterize.sh   (rewrites golden.txt)
# Debug:   CHARACTERIZE_OUT=<file> keeps the produced capture; CHARACTERIZE_KEEP=1 keeps the scratch dir;
#          CHARACTERIZE_PYTHON=<python3> picks the interpreter (the golden must hold on every one);
#          CHARACTERIZE_KIT=<dir> runs the entry points of another tree (a copy with bin and lib), which
#          is how a negative control mutates a temp copy and watches a section go red.
set -uo pipefail

HERE_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
KIT="${CHARACTERIZE_KIT:-$HERE_KIT}"
FIX="$HERE_KIT/tests/fixtures/sync-characterize"
GOLDEN="$FIX/golden.txt"
DELTAS="$FIX/deltas.txt"
TAGS="describe-line board-help sweep-help apps-default apps-hint unknown-app sweep-unknown-arg health-brief-help"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

W_RAW="$(mktemp -d "${TMPDIR:-/tmp}/char.XXXXXX")" || exit 1
W="$(cd "$W_RAW" && pwd -P)"
[ "${CHARACTERIZE_KEEP:-0}" = 1 ] || trap 'command rm -rf "$W"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_DATE="2026-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2026-01-01T00:00:00+0000"

PY="${CHARACTERIZE_PYTHON:-$(command -v python3)}"
PY="$("$PY" -c 'import sys; print(sys.executable)')"
STUBS="$W/home/.local/bin"
BASEPATH="/usr/bin:/bin:/usr/sbin:/sbin"
GUARD_NAMES="ssh scp osascript gh ntn hermes curl wget op secret-cache-read nc"
mkdir -p "$STUBS" "$W/tmp" "$W/data" "$W/opcfg" "$W/kitroot" "$W/guard" "$W/state"
: > "$W/stub.log"; : > "$W/guard.log"
printf '[sync]\n' > "$W/kitroot/kit.toml"

# ---- the stubs -----------------------------------------------------------------------------------
# One recorder serves every transport program: it logs the call and prints canned data. The python3
# entry is a symlink to the real interpreter, so a `python3` in the sweep's widened PATH is the same one.
cat > "$STUBS/.recorder" <<'EOF'
#!/bin/bash
n="${0##*/}"
{ printf '%s' "$n"; for a in "$@"; do a="${a//$'\n'/ }"; printf '\t%s' "${a:0:100}"; done; printf '\n'; } >> "${CHAR_STUB_LOG:?}"
case "$n" in
  osascript|gh) printf '[]\n' ;;
  secret-cache-read|op) printf 'stub-token\n' ;;
  ssh) sed 's/^/  | /' >> "$CHAR_STUB_LOG" ;;
esac
exit 0
EOF
chmod +x "$STUBS/.recorder"
for n in $GUARD_NAMES; do
  [ "$n" = hermes ] && continue
  ln -s .recorder "$STUBS/$n"
done
ln -s "$PY" "$STUBS/python3"

# hermes: the kanban CLI the mirror and writeback bridge call. Write verbs answer like the real CLI;
# `list --json` replays $CHAR_KANBAN_LIST (an empty list when unset).
cat > "$STUBS/hermes" <<'EOF'
#!/bin/bash
{ printf 'hermes'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "${CHAR_STUB_LOG:?}"
[ "${1:-}" = kanban ] || exit 0
shift
if [ "${1:-}" = "--board" ]; then board="$2"; shift 2; fi
case "${1:-}" in
  create)
    f="${CHAR_STUB_STATE:?}/idcounter"
    n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$f"
    printf '{"id":"t_stub%03d","title":"stub"}\n' "$n" ;;
  block)    echo "moved (stub)" ;;
  promote)  echo "Promoted (stub)" ;;
  archive)  echo "Archived (stub)" ;;
  complete) echo "Completed (stub)" ;;
  comment)  echo "commented (stub)" ;;
  list)     if [ -n "${CHAR_KANBAN_LIST:-}" ] && [ -f "$CHAR_KANBAN_LIST" ]; then cat "$CHAR_KANBAN_LIST"; else echo '[]'; fi ;;
  show)     echo '{}' ;;
  *) echo "hermes stub: unhandled verb ${1:-}" >&2; exit 1 ;;
esac
EOF
chmod +x "$STUBS/hermes"

# ---- the transport guard ---------------------------------------------------------------------------
cat > "$W/guard/sitecustomize.py" <<'EOF'
import os
if os.environ.get("CHAR_GUARD_LOG"):
    import shlex
    import shutil
    import socket
    import subprocess
    _LOG = os.environ["CHAR_GUARD_LOG"]
    _STUBS = os.path.realpath(os.environ["CHAR_STUB_DIR"])
    _NAMES = set(os.environ.get("CHAR_GUARD_NAMES", "").split())

    def _violation(what):
        with open(_LOG, "a") as f:
            f.write(what + "\n")
        raise RuntimeError("characterize transport guard: " + what)

    def _check_exe(exe, env):
        if os.path.basename(exe) not in _NAMES:
            return
        found = exe if os.sep in exe else shutil.which(exe, path=(env or os.environ).get("PATH"))
        if not found or not os.path.realpath(found).startswith(_STUBS + os.sep):
            _violation("program outside the stub directory: " + exe)

    _init = subprocess.Popen.__init__

    def _popen_init(self, args, *a, **k):
        if isinstance(args, (list, tuple)):
            exe = os.fspath(args[0]) if args else ""
        elif isinstance(args, str) and k.get("shell"):
            exe = (shlex.split(args) or [""])[0]
        else:
            exe = os.fspath(args)
        _check_exe(exe, k.get("env"))
        return _init(self, args, *a, **k)

    subprocess.Popen.__init__ = _popen_init
    _system = os.system

    def _os_system(cmd):
        _check_exe((shlex.split(cmd) or [""])[0], None)
        return _system(cmd)

    os.system = _os_system
    _LOCAL = ("127.0.0.1", "::1", "localhost", "")
    _connect, _connect_ex = socket.socket.connect, socket.socket.connect_ex

    def _guard_addr(sock, address):
        if sock.family in (socket.AF_INET, socket.AF_INET6) and address[0] not in _LOCAL:
            _violation("socket connect to " + str(address[0]))

    def _sock_connect(self, address):
        _guard_addr(self, address)
        return _connect(self, address)

    def _sock_connect_ex(self, address):
        _guard_addr(self, address)
        return _connect_ex(self, address)

    socket.socket.connect, socket.socket.connect_ex = _sock_connect, _sock_connect_ex
    _gai = socket.getaddrinfo

    def _getaddrinfo(host, *a, **k):
        if host not in (None,) + _LOCAL:
            _violation("name lookup " + str(host))
        return _gai(host, *a, **k)

    socket.getaddrinfo = _getaddrinfo
EOF

# cenv <cwd> [VAR=val ...] <cmd...>: run in the isolated environment. Later assignments win.
cenv() {
  local cwd="$1"; shift
  ( cd "$cwd" && env -i HOME="$W/home" PATH="$STUBS:$BASEPATH" TMPDIR="$W/tmp" LANG=C LC_ALL=C TZ=UTC \
      COLUMNS=200 NO_COLOR=1 PYTHONHASHSEED=0 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$W/guard" \
      KIT_CONFIG_OPERATOR="$W/opcfg" KIT_CONFIG_ROOT="$W/kitroot" KIT_DATA_ROOT="$W/data" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      CHAR_STUB_LOG="$W/stub.log" CHAR_STUB_DIR="$STUBS" CHAR_STUB_STATE="$W/state" \
      CHAR_GUARD_LOG="$W/guard.log" CHAR_GUARD_NAMES="$GUARD_NAMES" CHAR_KIT="$KIT" \
      "$@" )
}

# ---- normalization ---------------------------------------------------------------------------------
sed_esc() { printf '%s' "$1" | sed 's/[][\.*^$/#|+?(){}]/\\&/g'; }
norm() {
  sed -E \
    -e "s#$(sed_esc "$W")#<W>#g" -e "s#$(sed_esc "$W_RAW")#<W>#g" -e "s#$(sed_esc "$KIT")#<KIT>#g" \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z?/<TS>/g' \
    -e 's/(origin\.[A-Za-z0-9_-]+)\.[0-9]+\.md/\1.<PID>.md/g' \
    -e 's/(board-(mirror|sweep)[A-Za-z-]*\.)[A-Za-z0-9]{6}/\1<RAND>/g' \
    -e 's/\[[0-9a-f]{8}\]/[<NONCE>]/g'
}

# ---- helpers shared by the sections ------------------------------------------------------------------
# git_seed <dir> <epoch>: commit everything in <dir> at a fixed time.
git_seed() {
  git -C "$1" add -A >/dev/null 2>&1
  GIT_AUTHOR_DATE="@$2 +0000" GIT_COMMITTER_DATE="@$2 +0000" git -C "$1" commit -q -m seed
}
# repo_with_origin <dir> <epoch>: a repo with a bare local origin, so a fetch never leaves the host.
repo_with_origin() {
  git_seed "$1" "$2"
  git clone -q --bare "$1" "$1.origin.git"
  git -C "$1" remote add origin "$1.origin.git"
  git -C "$1" fetch -q origin
  git -C "$1" remote set-head origin main >/dev/null 2>&1
}
# drain_logs: print the stub call log and the guard log, then empty them.
drain_logs() {
  if [ -s "$W/stub.log" ]; then printf 'stub calls:\n'; sed 's/^/  /' "$W/stub.log"; fi
  if [ -s "$W/guard.log" ]; then printf 'GUARD VIOLATION:\n'; sed 's/^/  /' "$W/guard.log"; fi
  : > "$W/stub.log"
}

BOARD_ROWS='# Backlog
## Active queue
| ID | Item | Notes & source | Status |
|----|------|-----------------|--------|
| ID-1 | Do the thing | #u-hi #f-mid first row | queued |
| ID-2 | Claimed thing | notes2 | claimed |
| ID-3 | Executing thing | notes3 | executing |
| ID-4 | Parked thing | notes4 | parked |
| ID-5 | Shipped thing | notes5 | shipped |
| ID-6 | Bound thing | notion-page:0123456789abcdef0123456789abcdef | queued |'

# ---- python helpers (stdlib only, run with the real interpreter) --------------------------------------
cat > "$W/norm_argv.py" <<'EOF'
import json
import sys

n = int(sys.argv[1])
args, env = [], []
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("ARG\t"):
        args.append(line[4:])
    elif line.startswith("ENV\t"):
        env.append(line[4:])
if not args:
    print("(engine not reached)")
    sys.exit(0)
engine, rest = args[0], args[1:]
caller = rest[len(rest) - n:] if n else []
cfg = rest[:len(rest) - n] if n else rest
apps, filters, opts = None, [], []
for i in range(0, len(cfg), 2):
    flag, val = cfg[i], cfg[i + 1] if i + 1 < len(cfg) else None
    if flag == "--apps" and apps is None:
        apps = val
    elif flag == "--filter":
        filters.append(val)
    else:
        opts.append((flag, val))
print("engine\t" + engine)
print("apps\t" + json.dumps(apps))
for flag, val in sorted(opts):
    print("opt\t%s\t%s" % (flag, json.dumps(val)))
for val in sorted(filters):
    print("filter\t" + json.dumps(val))
for val in caller:
    print("caller\t" + json.dumps(val))
for e in env:
    print("env\t" + e)
EOF

cat > "$W/help_reduce.py" <<'EOF'
import re
import sys

text = sys.stdin.read().splitlines()
blocks, cur = [], None
for line in text:
    if re.match(r"^  -", line):
        cur = [line.strip()]
        blocks.append(cur)
    elif cur is not None and re.match(r"^ {10,}\S", line):
        cur.append(line.strip())
    else:
        cur = None
rows = []
for b in blocks:
    first = b[0]
    parts = re.split(r"\s{2,}", first, maxsplit=1)
    opt = parts[0]
    helptext = " ".join(([parts[1]] if len(parts) > 1 else []) + b[1:])
    flags = ",".join(re.findall(r"--[a-z][a-z-]*|(?<!-)-h\b", opt))
    rows.append((flags, " ".join(helptext.split())))
for flags, helptext in sorted(rows):
    print("%s\t%s" % (flags, helptext))
EOF

# ==================================================================================================
# section 1: `board sync` argv over a config matrix
# ==================================================================================================
S1BIN="$W/s1bin"; mkdir -p "$S1BIN"
cat > "$S1BIN/python3" <<'EOF'
#!/bin/bash
printf 'ARG\t%s\n' "$@"
if [ -n "${MULTICA_TOKEN:-}" ]; then t=set; else t=unset; fi
printf 'ENV\tMULTICA_TOKEN=%s\n' "$t"
printf 'ENV\tKIT_PROJECT_ROOT=%s\n' "${KIT_PROJECT_ROOT:-unset}"
EOF
chmod +x "$S1BIN/python3"

# s1_case <name> <project toml> <operator toml> [VAR=val ...] -- <caller args...>
# The caller args come last in the engine argv, because they win.
s1_case() {
  local name="$1" proj="$2" opcfg="$3"; shift 3
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  local ntail=$#
  local d="$W/s1/$name"; mkdir -p "$d/_meta" "$d/op"
  : > "$d/_meta/BACKLOG.md"
  git -C "$d" init -q -b main
  [ -n "$proj" ] && printf '%s\n' "$proj" > "$d/.kit.toml"
  printf '%s\n' "$opcfg" > "$d/op/kit.toml"
  : > "$W/stub.log"
  local out rc
  out="$(cenv "$d" PATH="$S1BIN:$STUBS:$BASEPATH" KIT_CONFIG_OPERATOR="$d/op" ${envs[@]+"${envs[@]}"} \
         "$KIT/bin/board" sync --backlog-file "$d/_meta/BACKLOG.md" "$@" 2>"$d/err")"; rc=$?
  printf '### %s\n' "$name"
  printf '%s\n' "$out" | "$PY" -I "$W/norm_argv.py" "$ntail"
  printf 'rc\t%s\n' "$rc"
  sed 's/^/stderr\t/' "$d/err"
  if [ -s "$W/stub.log" ]; then sed 's/^/lookup\t/' "$W/stub.log"; : > "$W/stub.log"; fi
}

S1_ALL_PROJECT='[sync]
apps = "reminders,notion,hermes,github,multica,notion-taskboard"
scope_exit_cap = 7
archive_file = "BACKLOG-archive.md"
reminders_list = "ListA"
reminders_only_tags = "alpha,beta"
reminders_skip_tags = "gamma"
reminders_intake = "all"
notion_db = "db-1"
notion_parent = "page-1"
notion_title = "Board"
notion_only_tags = "n1"
notion_skip_tags = "n2"
notion_intake = "none"
hermes_target = "box"
hermes_home = "/srv/h"
hermes_board = "crew"
hermes_assignee = "bot"
hermes_workspace = "dir:/w/{id}"
hermes_only_tags = "h1"
hermes_skip_tags = "h2"
hermes_intake = "all"
multica_workspace = "ws-1"
multica_project = "pj-1"
multica_only_tags = "m1"
multica_skip_tags = "m2"
multica_intake = "none"
github_repo = "o/r"
github_only_tags = "g1"
github_skip_tags = "g2"
github_intake = "all"
notion_taskboard_db = "tb-1"
notion_taskboard_status_map = "queued=Backlog,executing=In progress"
notion_taskboard_status_default = "Backlog"
notion_taskboard_priority_map = "u-hi=P0"
notion_taskboard_weight_map = "f-hi=2"
notion_taskboard_owner = "user-1"
notion_taskboard_props = "{}"
notion_taskboard_types = "{}"
notion_taskboard_only_tags = "t1"
notion_taskboard_skip_tags = "t2"
notion_taskboard_pull_db = "pull-1"
notion_taskboard_pull_props = "{}"
notion_taskboard_pull_done_option = "Shipped"'

section_1() {
  s1_case all-keys "$S1_ALL_PROJECT" '[sync]
multica_url = "https://operator.example"
multica_token_ref = "op://operator/ref"' -- 
  s1_case legacy-sources-alias '[sync]
sources = "hermes"
hermes_home = "/h"
hermes_target = "t"' '' -- 
  s1_case legacy-surfaces-alias '[sync]
surfaces = "reminders"' '' -- 
  s1_case multica-project-only '[sync]
apps = "multica"
multica_url = "https://project.example"
multica_token_ref = "op://project/ref"
multica_workspace = "w"
multica_project = "p"' '' -- 
  s1_case multica-operator '[sync]
apps = "multica"
multica_workspace = "w"
multica_project = "p"' '[sync]
multica_url = "https://operator.example"
multica_token_ref = "op://operator/ref"' -- 
  s1_case multica-token-preset '[sync]
apps = "multica"' '[sync]
multica_url = "https://operator.example"
multica_token_ref = "op://operator/ref"' MULTICA_TOKEN=preset --
  s1_case relay-hermes '[sync]
apps = "notion-taskboard"
notion_taskboard_db = "tb-1"
notion_taskboard_status_default = "Backlog"' '' -- --apps hermes \
    --filter hermes:only_tags=notion-intake --filter hermes:intake=all \
    --filter 'hermes:intake_skip_re=^filed-by: bot' --hermes-target box --hermes-home /srv/h \
    --hermes-board crew --hermes-assignee bot --hermes-workspace 'dir:/w/{id}' --notion-taskboard-db ""
  s1_case pull-intake '[sync]
apps = "notion-taskboard-pull"
notion_taskboard_pull_db = "pull-1"' '' -- --apps notion-taskboard-pull \
    --notion-taskboard-pull-db pull-1 --notion-taskboard-db ""
  s1_case caller-dry-run '[sync]
apps = "reminders"
reminders_list = "ListA"' '' -- --dry-run --scope-exit-cap 3
  s1_case unconfigured '' '' -- 
  s1_case unconfigured-empty-sync '[sync]
sources = ""' '' -- 
}

# ==================================================================================================
# section 2: the engine's flag surface
# ==================================================================================================
section_2() {
  cenv "$W" "$PY" "$KIT/lib/sync/backlog_sync.py" --help 2>&1 | "$PY" -I "$W/help_reduce.py"
}

# ==================================================================================================
# section 7: help text and error paths
# ==================================================================================================
section_7() {
  local d="$W/s7"; mkdir -p "$d/_meta"
  printf '%s\n' "$BOARD_ROWS" > "$d/_meta/BACKLOG.md"
  git -C "$d" init -q -b main
  local out rc
  printf '### board help\n'
  cenv "$d" "$KIT/bin/board" help 2>&1; printf 'rc\t%s\n' "$?"
  printf '### unknown verb\n'
  out="$(cenv "$d" "$KIT/bin/board" bogusverb --backlog-file "$d/_meta/BACKLOG.md" 2>&1)"; rc=$?
  printf '%s\nrc\t%s\n' "$out" "$rc"
  # no --apps: today's default is a live Reminders sync, so it only ever runs with --dry-run,
  # a scratch state root and the osascript stub
  : > "$W/stub.log"
  printf '### engine without --apps\n'
  out="$(cenv "$d" "$PY" "$KIT/lib/sync/backlog_sync.py" --backlog "$d/_meta/BACKLOG.md" \
         --state-root "$W/s7state-a" --dry-run 2>&1)"; rc=$?
  printf '%s\nrc\t%s\n' "$(printf '%s\n' "$out" | sed -n '1p')" "$rc"
  drain_logs
  printf '### engine with an unknown app\n'
  out="$(cenv "$d" "$PY" "$KIT/lib/sync/backlog_sync.py" --backlog "$d/_meta/BACKLOG.md" \
         --state-root "$W/s7state-b" --apps bogus --dry-run 2>&1)"; rc=$?
  printf '%s\nrc\t%s\n' "$(printf '%s\n' "$out" | sed -n '1p')" "$rc"
  drain_logs
  printf '### sweep with an unknown flag\n'
  out="$(cenv "$d" "$KIT/bin/board" sweep --bogus-flag 2>&1)"; rc=$?
  printf '%s\nrc\t%s\n' "$out" "$rc"
}

# ==================================================================================================
# the guard and the run
# ==================================================================================================
SECTIONS="1-sync-argv:section_1 2-engine-flags:section_2 7-help-errors:section_7"

# guard_paths_ok <stub dir> <PATH>: every transport program resolves into the stub dir.
guard_paths_ok() {
  local n found
  for n in $GUARD_NAMES; do
    found="$(PATH="$2" command -v "$n" 2>/dev/null || true)"
    case "$found" in "$1"/*) ;; *) printf '%s resolves to %s\n' "$n" "${found:-nothing}"; return 1 ;; esac
  done
}

echo "=== guard ==="
bad_names="$(guard_paths_ok "$STUBS" "$STUBS:/opt/homebrew/bin:/usr/local/bin:$BASEPATH")" \
  && ok "every transport program resolves into the stub directory (also on the sweep's widened PATH)" \
  || bad "a transport program is not stubbed: $bad_names"
empty_dir="$W/nostubs"; mkdir -p "$empty_dir"
if guard_paths_ok "$empty_dir" "$BASEPATH" >/dev/null 2>&1; then
  bad "the PATH check passes with the stubs hidden"
else ok "negative control: with the stubs hidden the PATH check fails"; fi
mkdir -p "$W/outside"; printf '#!/bin/bash\nexit 0\n' > "$W/outside/curl"; chmod +x "$W/outside/curl"
: > "$W/guard.log"
cenv "$W" "$PY" -c 'import subprocess,sys; subprocess.run([sys.argv[1]])' "$W/outside/curl" >/dev/null 2>&1
if [ -s "$W/guard.log" ]; then ok "negative control: a program outside the stub directory trips the guard"
else bad "the subprocess guard did not trip on a bypassed stub"; fi
: > "$W/guard.log"
cenv "$W" "$PY" -c 'import socket; socket.create_connection(("192.0.2.1", 9), timeout=1)' >/dev/null 2>&1
if [ -s "$W/guard.log" ]; then ok "negative control: a non-loopback connect trips the guard"
else bad "the socket guard did not trip on a non-loopback connect"; fi
: > "$W/guard.log"; : > "$W/stub.log"
hits="$(cd "$HERE_KIT" && git grep -nE '(/usr/bin|/usr/local/bin|/opt/homebrew/bin|/bin)/(ssh|scp|osascript|gh|ntn|hermes|curl|wget|op|secret-cache-read)([^A-Za-z0-9_-]|$)' -- lib/board lib/sync lib/config bin | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
[ -z "$hits" ] && ok "no entry point calls a transport program by absolute path" || bad "absolute transport path: $hits"

echo "=== capture ==="
OUT="$W/actual.txt"; : > "$OUT"
for entry in $SECTIONS; do
  name="${entry%%:*}"; fn="${entry#*:}"
  printf '## %s\n' "$name" >> "$OUT"
  "$fn" 2>&1 | norm >> "$OUT"
  if [ -s "$W/guard.log" ]; then
    bad "transport guard tripped in section $name: $(tr '\n' ';' < "$W/guard.log")"; : > "$W/guard.log"
  fi
done
[ -n "${CHARACTERIZE_OUT:-}" ] && cp "$OUT" "$CHARACTERIZE_OUT"

if [ "${CHARACTERIZE_UPDATE:-0}" = 1 ]; then
  mkdir -p "$FIX"; cp "$OUT" "$GOLDEN"
  echo "golden updated: $GOLDEN"
  [ "$FAIL" -eq 0 ]; exit
fi

# split a capture into one file per section
split_sections() {  # <capture> <dir>
  mkdir -p "$2"
  awk -v d="$2" '/^## /{ f = d "/" substr($0, 4); printf "" > f; next } f { print > f }' "$1"
}

echo "=== sections ==="
if [ ! -f "$GOLDEN" ]; then bad "no golden at $GOLDEN (run with CHARACTERIZE_UPDATE=1 on a clean tree)"; fi
if [ -f "$GOLDEN" ]; then
  split_sections "$GOLDEN" "$W/cmp/golden"; split_sections "$OUT" "$W/cmp/actual"
  for entry in $SECTIONS; do
    name="${entry%%:*}"
    if [ ! -s "$W/cmp/actual/$name" ]; then bad "section $name is empty"
    elif [ ! -f "$W/cmp/golden/$name" ]; then bad "section $name is missing from the golden"
    elif cmp -s "$W/cmp/golden/$name" "$W/cmp/actual/$name"; then ok "section $name matches the golden"
    else
      bad "section $name differs from the golden"
      diff -u "$W/cmp/golden/$name" "$W/cmp/actual/$name" | sed -n '1,60p' | sed 's/^/      /'
    fi
  done
  for f in "$W/cmp/golden"/*; do
    [ -f "$f" ] || continue
    n="$(basename "$f")"
    case " $SECTIONS " in *" $n:"*) ;; *) bad "the golden holds a section this suite no longer produces: $n" ;; esac
  done
fi

echo "=== deltas ==="
if [ -f "$DELTAS" ]; then
  while IFS="$(printf '\t')" read -r dsec dtag; do
    [ -n "$dsec$dtag" ] || continue
    case " $TAGS " in *" $dtag "*) ;; *) bad "deltas.txt: tag '$dtag' is not in the closed list" ;; esac
    [ -f "$W/cmp/golden/$dsec" ] || bad "deltas.txt: section '$dsec' is not in the golden"
  done < "$DELTAS"
  ok "deltas.txt rows are in the closed list"
else bad "no deltas.txt at $DELTAS"; fi

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
