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
#   3-engine-dry-run each of the seven apps through build_source and sync_source(dry_run) with a canned fake
#   4-sweep          `board sweep`: no leg flags, the three leg flags, the same with --dry-run, --health, --help
#   5-health-brief   `board health` and `board brief`: both --help outputs, run --dry-run over a fixture registry
#   6-bridge-verbs   mirror (dry run, apply, again), status (with and without --with-mega), writeback --dry-run,
#                    mirror-cleanup, hermes check and link --help
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
# The boundary lint scans fixture text for the operator's repo name and `board help` prints it, so the
# golden carries that name as ops-<NAME>. A 64-hex row hash keeps its first 12 hex digits: the commit scan
# refuses a 64-hex string as a possible key, and 48 bits still change whenever a row's content does.
sed_esc() { printf '%s' "$1" | sed 's/[][\.*^$/#|+?(){}]/\\&/g'; }
norm() {
  sed -E \
    -e "s#$(sed_esc "$W")#<W>#g" -e "s#$(sed_esc "$W_RAW")#<W>#g" -e "s#$(sed_esc "$KIT")#<KIT>#g" \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z?/<TS>/g' \
    -e 's/(origin\.[A-Za-z0-9_-]+)\.[0-9]+\.md/\1.<PID>.md/g' \
    -e 's/(board-(mirror|sweep)[A-Za-z-]*\.)[A-Za-z0-9]{6}/\1<RAND>/g' \
    -e 's/\[[0-9a-f]{8}\]/[<NONCE>]/g' \
    -e 's/key=[0-9a-f]{32}/key=<KEY>/g' \
    -e "s/ops-""toolkit/ops-<NAME>/g" \
    -e 's/([0-9a-f]{12})[0-9a-f]{52,}/\1<hash>/g'
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
# section 3: the engine dry run of each app, through build_source and sync_source
# ==================================================================================================
# The harness imports backlog_sync and calls build_source(name, args) then sync_source(..., dry_run=True),
# the two seams that stay in place after every move. Each source's transport (`runner`) is replaced by a
# canned fake lifted from that app's own unit tests; a call a fake does not script raises, and the
# transport guard raises on any real subprocess or socket.
cat > "$W/engine_dryrun.py" <<'EOF'
import argparse
import contextlib
import io
import json
import os
import sys
from pathlib import Path

kit = Path(os.environ["CHAR_KIT"])
backlog = Path(sys.argv[1])
work = backlog.parent.parent
sys.path.insert(0, str(kit / "lib" / "sync"))
sys.path.insert(0, str(kit / "lib" / "config"))
os.environ["MULTICA_TOKEN"] = "fixture"
import backlog_sync as bs  # noqa: E402

# every option of the engine, under the config key and, for the one dest that differs today, the legacy dest
KEYS = ["reminders_list", "list_name", "notion_db", "notion_parent", "notion_title", "github_repo",
        "hermes_target", "hermes_home", "hermes_board", "hermes_assignee", "hermes_workspace",
        "notion_taskboard_db", "notion_taskboard_status_map", "notion_taskboard_status_default",
        "notion_taskboard_priority_map", "notion_taskboard_weight_map", "notion_taskboard_owner",
        "notion_taskboard_props", "notion_taskboard_types", "notion_taskboard_pull_db",
        "notion_taskboard_pull_props", "notion_taskboard_pull_done_option",
        "multica_url", "multica_workspace", "multica_project"]


def ns(**kw):
    base = {k: None for k in KEYS}
    if "reminders_list" in kw:
        base["list_name"] = kw["reminders_list"]
    base.update(kw)
    return argparse.Namespace(**base)


def title(bid, text):
    return "%s · %s" % (bid, text)


# ---- the fakes ------------------------------------------------------------------------------------
def fake_reminders(rec):
    def run(script, *args):
        rec.append({"args": list(args)})
        if list(args) != ["Backlog"] or "rems.id()" not in script:
            raise AssertionError("unscripted reminders call: %r" % (args,))
        return json.dumps([
            {"rid": "r1", "title": title("ID-1", "Do the thing"), "body": "", "completed": False},
            {"rid": "r2", "title": title("ID-3", "Executing thing"), "body": "", "completed": True},
            {"rid": "r3", "title": "Idea captured on the phone", "body": "", "completed": False}])
    return run


def fake_ntn(rec, schema, pages):
    def run(args, data=None):
        a = list(args)
        rec.append({"args": a, "data": data})
        if a[:2] == ["datasources", "resolve"]:
            return {"data_sources": [{"id": "ds-" + a[2]}]}
        if a[0] == "api" and a[1].startswith("v1/data_sources/"):
            if a[1].endswith("/query"):
                return {"results": pages, "has_more": False}
            return schema
        raise AssertionError("unscripted ntn call: %r" % (a,))
    return run


NOTION_SCHEMA = {"properties": {
    "Name": {"type": "title", "title": {}},
    "Status": {"type": "select", "select": {"options": [{"name": "queued"}, {"name": "shipped"}]}},
    "Notes": {"type": "rich_text", "rich_text": {}},
    "Tags": {"type": "multi_select", "multi_select": {}}}}
NOTION_PAGES = [
    {"id": "pg-1", "properties": {
        "Name": {"title": [{"plain_text": title("ID-1", "Do the thing")}]},
        "Status": {"select": {"name": "executing"}}, "Notes": {"rich_text": []},
        "Tags": {"multi_select": []}}},
    {"id": "pg-2", "properties": {
        "Name": {"title": [{"plain_text": "Page made in Notion"}]},
        "Status": {"select": {"name": "queued"}}, "Notes": {"rich_text": [{"plain_text": "note"}]},
        "Tags": {"multi_select": [{"name": "idea"}]}}}]

TASKBOARD_SCHEMA = {"properties": {
    "Task": {"type": "title", "title": {}},
    "Status": {"type": "status", "status": {"options": [
        {"name": "Backlog"}, {"name": "In progress"}, {"name": "Waiting"}, {"name": "Done"}]}},
    "Priority": {"type": "select", "select": {"options": [{"name": "P0"}, {"name": "P1"}]}},
    "Weight": {"type": "number", "number": {}},
    "Owner": {"type": "people", "people": {}}}}

PULL_PAGES = [{"id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "properties": {
    "Task": {"title": [{"plain_text": "Fix the sync on the team board"}]},
    "Notes": {"rich_text": [{"plain_text": "details from a teammate"}]}}}]


def fake_github(rec):
    def run(argv):
        rec.append({"argv": list(argv)})
        if argv[:2] != ["issue", "list"]:
            raise AssertionError("unscripted gh call: %r" % (argv,))
        return json.dumps([
            {"number": 7, "title": title("ID-1", "Do the thing"), "state": "OPEN", "body": "b"},
            {"number": 8, "title": title("ID-5", "Shipped thing"), "state": "CLOSED", "body": ""}])
    return run


def fake_hermes(rec):
    def run(script):
        rec.append({"script": script})
        if "list --json" not in script:
            raise AssertionError("unscripted hermes call")
        live = [{"id": "t_1", "title": title("ID-2", "Claimed thing"), "status": "ready", "body": ""},
                {"id": "t_2", "title": "Card from a teammate", "status": "triage", "body": "from chat"}]
        archived = [{"id": "t_3", "title": title("ID-5", "Shipped thing"), "status": "archived", "body": ""}]
        return json.dumps(live) + "\n@@SEP@@\n" + json.dumps(archived) + "\n"
    return run


def fake_multica(rec):
    def run(method, path, body=None):
        rec.append({"method": method, "path": path, "body": body})
        if method != "GET":
            raise AssertionError("unscripted multica call: %s %s" % (method, path))
        return {"issues": [
            {"id": "mi_1", "title": title("ID-4", "Parked thing"), "status": "blocked", "description": "d"},
            {"id": "mi_2", "title": "Filed in Multica", "status": "todo", "description": "e"}], "total": 2}
    return run


APPS = [
    ("reminders", ns(reminders_list="Backlog"), lambda rec: fake_reminders(rec)),
    ("notion", ns(notion_db="db1", notion_title="Backlog"),
     lambda rec: fake_ntn(rec, NOTION_SCHEMA, NOTION_PAGES)),
    ("notion-taskboard", ns(notion_taskboard_db="tb1",
                            notion_taskboard_status_map="queued=Backlog,executing=In progress,parked=Waiting,shipped=Done",
                            notion_taskboard_status_default="Backlog",
                            notion_taskboard_priority_map="u-hi=P0,u-mid=P1",
                            notion_taskboard_weight_map="f-hi=2,f-mid=5"),
     lambda rec: fake_ntn(rec, TASKBOARD_SCHEMA, [])),
    ("notion-taskboard-pull", ns(notion_taskboard_pull_db="pull1"),
     lambda rec: fake_ntn(rec, {}, PULL_PAGES)),
    ("github", ns(github_repo="o/r"), lambda rec: fake_github(rec)),
    ("hermes", ns(hermes_target="box", hermes_home="/srv/hermes", hermes_board="crew"),
     lambda rec: fake_hermes(rec)),
    ("multica", ns(multica_url="https://multica.invalid", multica_workspace="ws", multica_project="pj"),
     lambda rec: fake_multica(rec)),
]

for app, args, make_fake in APPS:
    buf, rec = io.StringIO(), []
    try:
        with contextlib.redirect_stdout(buf):
            src = bs.build_source(app, args)
            src.runner = make_fake(rec)
            ok = bs.sync_source(src, backlog, work / ("%s.state.json" % app), True, filt=None, cap=20,
                                allow=0, allow_flips=0, archive=None, allow_closes=0)
        result = "clean" if ok else "refused"
    except SystemExit as e:
        result = "exit: %s" % (e.code,)
    except Exception as e:  # noqa: BLE001
        result = "error: %s: %s" % (type(e).__name__, e)
    print("### " + app)
    print("result\t" + result)
    print(buf.getvalue().rstrip("\n") or "(no output)")
    for c in rec:
        print("call\t" + json.dumps(c, sort_keys=True))

print("### missing flags")
for app, kw in [("hermes", {}), ("hermes", {"hermes_home": "/h"}), ("multica", {}),
                ("multica", {"multica_url": "u"}), ("notion-taskboard", {}),
                ("notion-taskboard", {"notion_taskboard_db": "d"}), ("notion-taskboard-pull", {}),
                ("bogus", {})]:
    try:
        bs.build_source(app, ns(**kw))
        print("%s %s\tbuilt" % (app, sorted(kw)))
    except SystemExit as e:
        print("%s %s\t%s" % (app, sorted(kw), e.code))
EOF

section_3() {
  local d="$W/s3"; mkdir -p "$d/_meta"
  printf '%s\n' "$BOARD_ROWS" > "$d/_meta/BACKLOG.md"
  git -C "$d" init -q -b main
  : > "$W/stub.log"
  cenv "$d" "$PY" "$W/engine_dryrun.py" "$d/_meta/BACKLOG.md"
  drain_logs
}

# ==================================================================================================
# section 4: `board sweep` over a fixture registry with a stub board command
# ==================================================================================================
s4_world() {
  local w="$W/s4"; mkdir -p "$w/crew/_meta" "$w/solo"
  printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| AB-1 | one | | queued |\n| AB-2 | two | | executing |\n' > "$w/crew/_meta/BACKLOG.md"
  git -C "$w/crew" init -q -b main; repo_with_origin "$w/crew" 1767225600
  printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| SO-1 | solo | | queued |\n' > "$w/solo/BACKLOG.md"
  git -C "$w/solo" init -q -b main; git_seed "$w/solo" 1767225600
  printf '%s\n' "crew  $w/crew/_meta/BACKLOG.md  on rail=crew" "solo  $w/solo/BACKLOG.md  rail=pers" > "$w/boards.txt"
  printf '[]\n' > "$w/kinds.json"
  printf '#!/bin/bash\ncat >> "$FAKE_POSTED"; echo >> "$FAKE_POSTED"\n' > "$w/poster"; chmod +x "$w/poster"
  cat > "$w/board" <<'EOF'
#!/bin/bash
{ printf 'board'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'
  printf '  env\tHERMES_HOME=%s\tGH_TOKEN=%s\tGIT_ASKPASS=%s\n' "${HERMES_HOME:-UNSET}" "${GH_TOKEN:-UNSET}" "${GIT_ASKPASS:-UNSET}"; } >> "${CHAR_STUB_LOG:?}"
case "${1:-}" in
  sync)
    if [ "$(basename "$PWD")" = crew ]; then printf 'synced reminders: 2 spoke items, 4 board rows\n  ~ board AB-2 -> shipped\n'
    else printf 'synced notion: 1 spoke items, 2 board rows\n(nothing to do)\n'; fi ;;
  publish) echo "publish stub" ;;
  mirror) echo "mirror stub plan applied" ;;
  mirror-cleanup) echo "expire stub: 0 archived" ;;
esac
exit 0
EOF
  chmod +x "$w/board"
}

# s4_run <label> <sweep args...>
s4_run() {
  local label="$1"; shift
  local w="$W/s4" out rc
  command rm -f "$w/digest.json" "$w/health.json"
  : > "$W/stub.log"
  printf '### %s\n' "$label"
  : > "$w/posted.out"
  out="$(cenv "$w" FAKE_POSTED="$w/posted.out" "$KIT/bin/board" sweep --registry "$w/boards.txt" --board-cmd "$w/board" \
         --repo-root "$w/crew" --state-file "$w/digest.json" --health-state-file "$w/health.json" \
         --name char "$@" 2>&1)"; rc=$?
  printf '%s\nrc\t%s\n' "$out" "$rc"
  drain_logs
  if [ -s "$w/posted.out" ]; then printf 'posted\t'; jq -r '[.kind, .cluster] | join(":")' "$w/posted.out" | paste -sd, -; fi
  if [ -s "$w/health.json" ]; then
    printf 'health state\t'; jq -S -c '{keys: keys, mirror_rc: (.mirror.rc // null), sync_repos: ((.sync // {}) | keys)}' "$w/health.json"
  fi
  if ls -A "$w/crew" 2>/dev/null | grep -q 'board-mirror-origin'; then echo "STRAY origin copy left in the repo root"; fi
}

section_4() {
  s4_world
  local w="$W/s4"
  local legs=(--mirror-hermes-home "$w/hermes-home" --mirror-snapshot "$w/snap.jsonl" --expire-kinds-file "$w/kinds.json")
  s4_run "no leg flags"
  s4_run "three leg flags" "${legs[@]}"
  s4_run "three leg flags, dry run" "${legs[@]}" --dry-run
  s4_run "three leg flags, the poster and the health leg" "${legs[@]}" --poster "$w/poster" \
    --cluster-map "alpha=crew,beta=pers" --health --health-force
  printf '### help\n'
  cenv "$w" "$KIT/bin/board" sweep --help 2>&1; printf 'rc\t%s\n' "$?"
}

# ==================================================================================================
# section 5: `board health` and `board brief` over a fixture registry and health state
# ==================================================================================================
section_5() {
  local w="$W/s5" now=1790000000 day=86400
  mkdir -p "$w/crew/_meta" "$w/solo"
  printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| AB-1 | one | | queued |\n| AB-2 | two | | executing |\n| AB-3 | waits | | parked [later] |\n| AB-4 | done | | shipped |\n| AB-5 | five | | claimed |\n' > "$w/crew/_meta/BACKLOG.md"
  git -C "$w/crew" init -q -b main; git_seed "$w/crew" $((now - 10 * day))
  git -C "$w/crew" clone -q --bare "$w/crew" "$w/crew.origin.git" 2>/dev/null
  git -C "$w/crew" remote add origin "$w/crew.origin.git"; git -C "$w/crew" fetch -q origin
  git -C "$w/crew" remote set-head origin main >/dev/null 2>&1
  printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| SO-1 | one | | queued |\n' > "$w/solo/BACKLOG.md"
  git -C "$w/solo" init -q -b main; git_seed "$w/solo" $((now - 1 * day))
  printf '%s\n' "crew  $w/crew/_meta/BACKLOG.md  on rail=crew" "solo  $w/solo/BACKLOG.md  rail=pers" > "$w/boards.txt"
  cat > "$w/kanban" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "boards list" ]; then
  printf '[{"slug":"work","archived":false,"counts":{"triage":2,"ready":1,"done":4,"archived":5}},{"slug":"crew","archived":false,"counts":{"ready":4}}]'
elif [ "$2" = "crew" ]; then
  printf '['; first=1
  for c in AB-1 AB-2 AB-3 AB-4; do
    [ "$first" -eq 0 ] && printf ','; first=0
    printf '{"id":"m-%s","status":"ready","body":"origin: crew:%s\\nnotes: x","created_at":%s}' "$c" "$c" "$((FAKE_NOW - 86400))"
  done
  printf ']'
else
  printf '[{"id":"a","title":"Fix the long running sync problem on the notion bridge","status":"triage","created_at":%s},{"id":"c","title":"Y","status":"triage","created_at":%s},{"id":"b","title":"Fine","status":"ready","created_at":%s}]' \
    "$((FAKE_NOW - 3 * 86400))" "$((FAKE_NOW - 2 * 86400))" "$((FAKE_NOW - 86400))"
fi
EOF
  cat > "$w/poster" <<'EOF'
#!/bin/bash
cat >> "$FAKE_POSTED"; echo >> "$FAKE_POSTED"
EOF
  chmod +x "$w/kanban" "$w/poster"
  local hs="$w/health.json" ds="$w/digest.json"
  echo '{}' > "$ds"; command rm -f "$hs"; : > "$w/posted.out"
  local common=(--registry "$w/boards.txt" --cluster-map "alpha=crew,beta=pers" --state-file "$ds"
                --health-state-file "$hs" --kanban "alpha=$w/kanban" --now "$now")
  local e=(FAKE_NOW="$now" FAKE_POSTED="$w/posted.out")
  : > "$W/stub.log"
  printf '### health help\n'; cenv "$w" "$KIT/bin/board" health --help 2>&1; printf 'rc\t%s\n' "$?"
  printf '### brief help\n'; cenv "$w" "$KIT/bin/board" brief --help 2>&1; printf 'rc\t%s\n' "$?"
  printf '### health run help\n'; cenv "$w" "$KIT/bin/board" health run --help 2>&1; printf 'rc\t%s\n' "$?"
  printf '### brief run help\n'; cenv "$w" "$KIT/bin/board" brief run --help 2>&1; printf 'rc\t%s\n' "$?"
  printf 'synced notion: 1 spoke items, 5 board rows\n' | cenv "$w" "$KIT/bin/board" health record --repo crew --rc 0 --now "$now" --health-state-file "$hs"
  printf 'synced notion: 1 spoke items, 1 board rows\n' | cenv "$w" "$KIT/bin/board" health record --repo solo --rc 0 --now "$now" --health-state-file "$hs"
  printf 'board-mirror: ERROR cannot complete t_8fbaac45\n' | cenv "$w" "$KIT/bin/board" health record --leg mirror --rc 0 --now "$now" --health-state-file "$hs"
  jq '.hermes_links = [{"label":"chief","profile":"p","cluster":"alpha","stale":true,"reason":"no stamp"}]' "$hs" > "$hs.tmp" && mv "$hs.tmp" "$hs"
  printf '### health state\n'; jq -S . "$hs"
  printf '### health run dry run\n'
  cenv "$w" "${e[@]}" "$KIT/bin/board" health run "${common[@]}" --poster "$w/poster" --dry-run 2>&1; printf 'rc\t%s\n' "$?"
  printf '### brief run dry run\n'
  cenv "$w" "${e[@]}" "$KIT/bin/board" brief run "${common[@]}" --poster "$w/poster" --hub alpha=crew --board alpha=work \
    --cluster alpha --dry-run 2>&1; printf 'rc\t%s\n' "$?"
  drain_logs
  [ ! -s "$w/posted.out" ] || echo "POSTED something in a dry run"
}

# ==================================================================================================
# section 6: the bridge verbs (mirror, status, writeback, mirror-cleanup, hermes) against stubs
# ==================================================================================================
cat > "$W/kanban_state.py" <<'EOF'
import json
import sys
import time

d = sys.argv[1]
now = int(time.time())


def card(cid, status, origin=None, by="user", title="t", age_days=0):
    body = "[AUTOMATED MIRROR]\norigin: %s\nnotes: n" % origin if origin else "free text"
    return {"id": cid, "title": title, "body": body, "status": status, "created_by": by,
            "created_at": now - age_days * 86400 - 3600}


json.dump([{"slug": s, "archived": False} for s in ("fixR", "megagoals", "chatter", "default")],
          open(d + "/boards.json", "w"))
json.dump([card("c1", "triage", "fixR:ID-001"), card("c2", "blocked", "fixR:ID-006"),
           card("c3", "triage", "fixR:ID-007"), card("c4", "blocked", "fixR:ID-008"),
           card("c5", "triage", "fixR:ID-099"), card("kid1", "scheduled", None, by="auto-decomposer"),
           card("c11", "triage", "fixZ:Z-1")], open(d + "/fixR.json", "w"))
json.dump([card("m1", "ready", "megagoals:fixR/mymega"), card("m3", "ready", "megagoals:fixR/ghost")],
          open(d + "/megagoals.json", "w"))
json.dump([card("s1", "triage", None, by="chat-desk", age_days=1),
           card("s2", "triage", None, by="chat-desk", age_days=9),
           card("s3", "triage", None, by="chat-aux", age_days=20)], open(d + "/chatter.json", "w"))
json.dump([card("i1", "blocked", None, title="[alarm] CRIT x")], open(d + "/default.json", "w"))
json.dump({"parents": [{"id": "kid1"}]}, open(d + "/show-c3.json", "w"))
EOF

s6_mega_world() {
  local w="$W/s6m"; mkdir -p "$w/boardrepo/_meta/megagoals/testmega/goals" "$w/coderoot"
  git -C "$w/coderoot" init -q -b master
  echo init > "$w/coderoot/README"; git_seed "$w/coderoot" 1767225600
  git -C "$w/coderoot" branch feat/testmega-03-gamma master
  git -C "$w/coderoot" branch feat/testmega-05-epsilon master
  git -C "$w/coderoot" checkout -q -b feat/testmega-06-zeta master
  echo a >> "$w/coderoot/README"; git -C "$w/coderoot" commit -qam "zeta 1"
  git -C "$w/coderoot" checkout -q master
  cat > "$w/boardrepo/_meta/megagoals/testmega/ROADMAP.md" <<'EOF'
# Mega-goal: testmega

## Sub-goals

- [x] 01-alpha (testrepo), does alpha, `auto`, PR #101 merged abc123def0 (shipped clean)
- [x] 02-beta (testrepo), does beta, `auto`, PR #999 merged deadbeef00 (roadmap claims merged, PR isn't)
- [ ] 03-gamma (testrepo), does gamma, `auto`, PR #
- [ ] 04-delta (testrepo), does delta, `auto`, PR #104
- [ ] 05-epsilon (testrepo), does epsilon, `auto`, PR #
- [ ] 06-zeta (testrepo), does zeta, `auto`, PR #
- [ ] 07-eta (testrepo), does eta, `auto`, PR #
- [~] 08-theta (testrepo), rehomed into a sibling mega, `auto`, PR #
EOF
  printf '**Branch:** feat/testmega-03-gamma\n' > "$w/boardrepo/_meta/megagoals/testmega/goals/03-gamma.md"
  printf '**Branch:** feat/testmega-05-epsilon\n' > "$w/boardrepo/_meta/megagoals/testmega/goals/05-epsilon.md"
  printf '**Branch:** feat/testmega-06-zeta\n' > "$w/boardrepo/_meta/megagoals/testmega/goals/06-zeta.md"
  printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-001 | Mega-goal: testmega | scaffold | queued |\n' > "$w/boardrepo/_meta/BACKLOG.md"
  git -C "$w/boardrepo" init -q -b main; git_seed "$w/boardrepo" 1767225600
  printf 'mega  %s/boardrepo/_meta/BACKLOG.md  off\n' "$w" > "$w/boards.txt"
  cat > "$w/gh" <<'EOF'
#!/bin/bash
printf 'gh' >> "${CHAR_STUB_LOG:?}"; for a in "$@"; do printf '\t%s' "$a" >> "$CHAR_STUB_LOG"; done; echo >> "$CHAR_STUB_LOG"
case "$1 $2" in
  "pr view") case "$3" in 101) echo MERGED ;; 999) echo OPEN ;; 104) echo MERGED ;; *) exit 1 ;; esac ;;
  "pr list") echo '[{"number":205,"headRefName":"feat/testmega-05-epsilon"}]' ;;
  *) echo "gh stub: unhandled call: $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$w/gh"
}

# s6_cmd <label> [VAR=val ...] -- <command...>: stdout and stderr kept apart, then the exit code and the stub calls
s6_cmd() {
  local label="$1" envs=(); shift
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  local w="$W/s6" out rc
  printf '### %s\n' "$label"
  out="$(cenv "$w" ${envs[@]+"${envs[@]}"} "$@" 2>"$w/err")"; rc=$?
  printf 'stdout:\n%s\nstderr:\n' "$out"; sed 's/^/  /' "$w/err"
  printf 'rc\t%s\n' "$rc"
  drain_logs
}

section_6() {
  local w="$W/s6" snap reg
  mkdir -p "$w/fixR/_meta/megagoals/mymega/goals" "$w/fixTrading/_meta"
  printf '# Backlog\n## Active queue\n| ID | Item | Notes & source | Status |\n|----|------|-----------------|--------|\n| ID-001 | Do the thing | some notes here | queued |\n| ID-002 | Claimed thing | notes2 | claimed |\n| ID-003 | Parked thing | notes3 | parked |\n| ID-004 | Executing thing | notes4 | executing |\n| ID-005 | Shipped thing | notes5 | shipped |\n' > "$w/fixR/_meta/BACKLOG.md"
  printf '# Mega-goal: My Test Mega\n\n- [x] 01-thing done, merged\n- [ ] 02-thing pending, `gate`, PR #12 awaiting review\n' > "$w/fixR/_meta/megagoals/mymega/ROADMAP.md"
  printf '# Backlog\n## Active queue\n| ID | Item | Notes & source | Status |\n|----|------|-----------------|--------|\n| TR-001 | Secret trading thing | should never mirror | queued |\n' > "$w/fixTrading/_meta/BACKLOG.md"
  git -C "$w/fixR" init -q -b main; repo_with_origin "$w/fixR" 1767225600
  git -C "$w/fixTrading" init -q -b main; git_seed "$w/fixTrading" 1767225600
  reg="$w/boards.txt"; snap="$w/snapshot.jsonl"
  printf '%s\n' "fixR  $w/fixR/_meta/BACKLOG.md  on rail=personal" "fixTrading  $w/fixTrading/_meta/BACKLOG.md  off" > "$reg"
  local flags=(--repo-root "$w" --registry "$reg" --snapshot "$snap")
  : > "$W/stub.log"; echo 0 > "$W/state/idcounter"
  s6_cmd "mirror dry run" -- "$KIT/bin/board" mirror --dry-run "${flags[@]}"
  s6_cmd "mirror apply" -- "$KIT/bin/board" mirror "${flags[@]}"
  printf '### snapshot after apply\n'; jq -S -c 'del(.seen_at)' "$snap" | sort
  s6_cmd "mirror again" -- "$KIT/bin/board" mirror "${flags[@]}"
  s6_cmd "status" -- "$KIT/bin/board" status "${flags[@]}"
  # a Hermes-side move for the writeback: the first card went to ready, the third to done
  local id1 id3
  id1="$(jq -r 'select(.origin=="fixR:ID-001").hermes_id' "$snap")"; id3="$(jq -r 'select(.origin=="fixR:ID-003").hermes_id' "$snap")"
  jq -nc --arg a "$id1" --arg b "$id3" '[{id:$a,status:"ready",title:"Do the thing"},{id:$b,status:"done",title:"Parked thing"}]' > "$w/list.json"
  s6_cmd "writeback dry run" CHAR_KANBAN_LIST="$w/list.json" -- "$KIT/bin/board" writeback --dry-run "${flags[@]}"
  # mirror-cleanup against the stateful kanban stub
  mkdir -p "$w/kstub"; cp "$HERE_KIT/tests/fixtures/board-sweep/stub-hermes-kanban" "$w/kanban-stub"; chmod +x "$w/kanban-stub"
  "$PY" -I "$W/kanban_state.py" "$w/kstub"
  printf '[{"kind":"alert","owner_rule":"closes with its ticket","match":{"title_prefix":"[alarm]"}},{"kind":"decomposer-child","owner_rule":"owned by its root","match":{"created_by":["auto-decomposer"]}},{"kind":"chatter","owner_rule":"expires by age","age_report":"archive chatter cards in triage after 14 days","match":{"board":"chatter","created_by":["chat-desk","chat-aux"]}}]\n' > "$w/kinds.json"
  jq -nc '{origin:"fixR:ID-001",repo:"fixR",id:"ID-001",board:"fixR",hermes_id:"c1",row_hash:"h",hermes_status:"triage",seen_at:"t"}' > "$w/cleanup-snap.jsonl"
  jq -nc '{origin:"fixR:ID-007",repo:"fixR",id:"ID-007",board:"fixR",hermes_id:"c3",row_hash:"h",hermes_status:"triage",seen_at:"t"}' >> "$w/cleanup-snap.jsonl"
  s6_cmd "mirror-cleanup" HERMES_BIN="$w/kanban-stub" STUB_DIR="$w/kstub" -- "$KIT/bin/board" mirror-cleanup \
    --registry "$reg" --snapshot "$w/cleanup-snap.jsonl" --hermes-home "$w/hermes-home" --kinds-file "$w/kinds.json" --source working
  printf 'kanban stub calls:\n'; sed 's/^/  /' "$w/kstub/calls.log"
  # the hermes link check: one profile linked, no skills installed, so it reads stale
  printf '{"links":[{"label":"chief","home":"%s/nohome","profile":"p","cluster":"alpha","skills_dir":"%s/noskills"}]}\n' "$w" "$w" > "$w/links.json"
  s6_cmd "hermes check" DWARVES_HERMES_LINKS="$w/links.json" -- "$KIT/bin/board" hermes check
  s6_cmd "hermes check with no links file" DWARVES_HERMES_LINKS="$w/none.json" -- "$KIT/bin/board" hermes check
  s6_cmd "hermes link help" -- "$KIT/bin/board" hermes link --help
  # status --with-mega over the mega fixture, gh stubbed through GH_BIN
  s6_mega_world
  local m="$W/s6m"
  s6_cmd "status with mega" GH_BIN="$m/gh" -- "$KIT/bin/board" status --with-mega --mega-code-root "$m/coderoot" \
    --repo-root "$m/boardrepo" --registry "$m/boards.txt" --snapshot "$m/none.jsonl"
  s6_cmd "board with mega" GH_BIN="$m/gh" -- "$KIT/bin/board" board --with-mega --mega-code-root "$m/coderoot" \
    --backlog-file "$m/boardrepo/_meta/BACKLOG.md"
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
SECTIONS="1-sync-argv:section_1 2-engine-flags:section_2 3-engine-dry-run:section_3 4-sweep:section_4 5-health-brief:section_5 6-bridge-verbs:section_6 7-help-errors:section_7"

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

# parts_differ <golden section> <actual section>: the `### <part>` names (an app, a case) whose text differs
parts_differ() {
  local d="$W/parts.$$" side f n names=""
  for side in golden actual; do
    mkdir -p "$d/$side"
    f="$1"; [ "$side" = actual ] && f="$2"
    awk -v d="$d/$side" '
      /^### / { n = substr($0, 5); k = n; gsub(/[^A-Za-z0-9._-]/, "_", k); cur = d "/" k; printf "" > cur
                print n >> (d "/.names"); next }
      { print >> (cur ? cur : d "/_head") }' "$f"
  done
  while IFS= read -r n; do
    k="$(printf '%s' "$n" | tr -c 'A-Za-z0-9._-' '_')"
    cmp -s "$d/golden/$k" "$d/actual/$k" 2>/dev/null || names="${names:+$names; }$n"
  done < <(cat "$d/golden/.names" "$d/actual/.names" 2>/dev/null | sort -u)
  if [ -e "$d/golden/_head" ] || [ -e "$d/actual/_head" ]; then
    cmp -s "$d/golden/_head" "$d/actual/_head" 2>/dev/null || names="${names:+$names; }(top)"
  fi
  printf '%s' "$names"
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
      bad "section $name differs from the golden in: $(parts_differ "$W/cmp/golden/$name" "$W/cmp/actual/$name")"
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
