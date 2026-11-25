#!/usr/bin/env bash
# test-state-check.sh -- `board state-check` (lib/board/state_check.py): the generic engine that checks the
# state values a repo stores against that repo's own registry file.
#
# Part 1: every rule against throwaway git repos (a block case blocks, a pass case passes), once with the
#         native TOML reader and once with the built-in one (the host Python may have no tomllib).
# Part 2: the registry and root arguments, the --all report, the exit codes, the importable surface.
# Part 3: negative control. Each rule is broken once in a COPY of the engine and the case that guards it
#         must go red. A case that stays green with its rule removed is a toothless test.
#
# Run: bash tests/test-state-check.sh        (PYTHON=/usr/bin/python3 bash tests/test-state-check.sh)
set -u

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$KIT_DIR/lib/board/state_check.py"
FIXREG="$KIT_DIR/tests/fixtures/state-check/states.toml"
PY="${PYTHON:-python3}"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  PASS $1"; }
no() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-state-check.XXXXXX")" || exit 1
TMPD="$(cd "$TMPD" && pwd)"
trap 'rm -rf "$TMPD"' EXIT

n=0
tm=""   # "" native reader, "mini" the built-in reader

new_repo() {
  n=$((n + 1))
  repo="$TMPD/r$n"
  mkdir -p "$repo/_meta" "$repo/gadgets/live" "$repo/gadgets/dead" "$repo/notes" "$repo/widgets/w1" "$repo/logs" "$repo/misc"
  cp "$FIXREG" "$repo/_meta/states.toml"
  printf 'name = "live"\nstatus = "ready"\n' >"$repo/gadgets/live/gadget.toml"
  printf 'name = "dead"\nstatus = "closed"\n' >"$repo/gadgets/dead/gadget.toml"
  printf -- '---\nstatus: snapshot\n---\nbody\n' >"$repo/notes/old.md"
  printf -- '---\nstatus: paused\n---\nbody\n' >"$repo/widgets/w1/README.md"
  printf '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | paused | 2026-01-01 |\n' >"$repo/widgets/INDEX.md"
  printf '| date | subject | verdict |\n|---|---|---|\n| 2026-01-01 | thing | GO |\n' >"$repo/logs/DECISIONS.md"
  git -c init.templateDir= -C "$repo" init -q
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m fixture
}

put() { # path content: write and stage
  mkdir -p "$(dirname "$repo/$1")"
  printf '%b' "$2" >"$repo/$1"
  git -C "$repo" add "$1"
}

eng() { # engine args...: run with the fixture repo as root; sets out and rc
  local e="$1"; shift
  out="$(STATES_ROOT="$repo" STATES_TOML="$tm" "$PY" "$e" "$@" 2>&1)"
  rc=$?
}

run() { eng "$1" --staged; }
expect_block() { run "$1"; [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q -- "$2"; }
expect_pass() { run "$1"; [ "$rc" -eq 0 ] && [ -z "$out" ]; }

case_undeclared() { new_repo; put gadgets/new/gadget.toml 'name = "new"\nstatus = "bogus"\n'; expect_block "$1" "'bogus' is not a declared state"; }
case_legacy_unchanged() { new_repo; put notes/old.md '---\nstatus: snapshot\n---\nbody changed\n'; expect_pass "$1"; }
case_legacy_new() { new_repo; put notes/new.md '---\nstatus: snapshot\n---\nbody\n'; expect_block "$1" "legacy value, refused when newly written"; }
case_illegal_transition() { new_repo; put gadgets/dead/gadget.toml 'name = "dead"\nstatus = "ready"\n'; expect_block "$1" "'closed' -> 'ready' is not a declared transition"; }
case_legal_transition() { new_repo; put gadgets/live/gadget.toml 'name = "live"\nstatus = "idle"\n'; expect_pass "$1"; }
case_new_file_declared() { new_repo; put gadgets/new/gadget.toml 'name = "new"\nstatus = "new"\n'; expect_pass "$1"; }
case_escape_hatch() {
  new_repo; put gadgets/dead/gadget.toml 'name = "dead"\nstatus = "ready"\n'
  out="$(ALLOW_STATE_CHANGE="fixture reason" STATES_ROOT="$repo" STATES_TOML="$tm" "$PY" "$1" --staged 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "reason: fixture reason" && printf '%s' "$out" | grep -q "ALLOWED by ALLOW_STATE_CHANGE"
}
case_drift_index_side() { new_repo; put widgets/INDEX.md '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | live | 2026-01-01 |\n'; expect_block "$1" "projection drift"; }
case_drift_store_side() { new_repo; put widgets/w1/README.md '---\nstatus: live\n---\nbody\n'; expect_block "$1" "projection drift"; }
case_drift_agreeing_edit() {
  new_repo
  put widgets/w1/README.md '---\nstatus: live\n---\nbody\n'
  put widgets/INDEX.md '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | live | 2026-01-01 |\n'
  expect_pass "$1"
}
case_drift_grandfathered() { # drift already at HEAD: an unrelated staged edit near it passes
  new_repo
  printf '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | live | 2026-01-01 |\n' >"$repo/widgets/INDEX.md"
  git -C "$repo" add -A; git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m drift
  put widgets/INDEX.md '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | live | 2026-02-02 |\n'
  expect_pass "$1"
}
case_append_only_past_row() { new_repo; put logs/DECISIONS.md '| date | subject | verdict |\n|---|---|---|\n| 2026-01-01 | thing | NO-GO |\n'; expect_block "$1" "past row edited"; }
case_append_only_append() { new_repo; put logs/DECISIONS.md '| date | subject | verdict |\n|---|---|---|\n| 2026-02-01 | other | HOLD |\n| 2026-01-01 | thing | GO |\n'; expect_pass "$1"; }
case_append_only_removed() { new_repo; put logs/DECISIONS.md '| date | subject | verdict |\n|---|---|---|\n'; expect_block "$1" "past row removed"; }
case_unmatched_file() { new_repo; put misc/other.md '---\nstatus: bogus\n---\nbody\n'; expect_pass "$1"; }
case_prefix_state() { new_repo; put notes/p.md '---\nstatus: current\nvisibility: published:abc123\n---\nbody\n'; expect_pass "$1"; }
case_table_transition() {
  new_repo
  printf '| artifact | status |\n|---|---|\n| a1 | done:ref |\n' >"$repo/logs/requests.md"
  git -C "$repo" add -A; git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m req
  put logs/requests.md '| artifact | status |\n|---|---|\n| a1 | open |\n'
  expect_block "$1" "'done:' -> 'open' is not a declared transition"
}
case_ignore_case_body_status() { new_repo; put specs/s1.md 'Title\n\nStatus: DRAFT\n\nbody\n'; expect_pass "$1"; }
case_ignore_case_undeclared() { new_repo; put specs/s2.md 'Title\n\nStatus: bogus\n\nbody\n'; expect_block "$1" "'bogus' is not a declared state"; }
case_ignore_case_transition_spelling() { # a registry spelled in Title case: a declared move passes, an undeclared one blocks
  new_repo
  printf '\n[ticket]\ncheck = true\nkind = "frontmatter"\nglob = "tickets/*.md"\nfield = "status"\nignore_case = true\nstates = ["Open", "Done"]\n\n[ticket.transitions]\nOpen = ["Done"]\nDone = []\n' >>"$repo/_meta/states.toml"
  mkdir -p "$repo/tickets"; printf -- '---\nstatus: open\n---\nbody\n' >"$repo/tickets/t1.md"; printf -- '---\nstatus: done\n---\nbody\n' >"$repo/tickets/t2.md"
  git -C "$repo" add -A; git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m tickets
  put tickets/t1.md '---\nstatus: DONE\n---\nbody\n'
  expect_pass "$1" || return 1
  put tickets/t2.md '---\nstatus: Open\n---\nbody\n'
  expect_block "$1" "'done' -> 'open' is not a declared transition"
}
case_unparseable_store() { new_repo; put gadgets/bad/gadget.toml 'name = = "x"\nstatus = [\n'; expect_pass "$1"; }
case_store_nested_field() { # a status inside a sub-table is not the top-level field
  new_repo; put gadgets/nest/gadget.toml 'name = "x"\n\n[meta]\nstatus = "bogus"\n'
  expect_pass "$1"
}
case_store_with_extra_toml() { # a store file using TOML the built-in reader lacks: its status still reads
  new_repo; put gadgets/rich/gadget.toml 'status = "bogus"\n\n[[run]]\nat = 2026-01-01T00:00:00Z\n'
  expect_block "$1" "'bogus' is not a declared state"
}

fix_run() { eng "$1" --fix; }
index_line() { grep -F "[$1]" "$repo/widgets/INDEX.md"; }

case_fix_drift() {
  new_repo
  printf '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | paused (waiting on review) | 2026-01-01 |\n' >"$repo/widgets/INDEX.md"
  printf -- '---\nstatus: live\n---\nbody\n' >"$repo/widgets/w1/README.md"
  fix_run "$1"
  [ "$rc" -eq 0 ] && [ "$(index_line w1)" = '| [w1](w1/) | live (waiting on review) | 2026-01-01 |' ] && printf '%s' "$out" | grep -q "'paused' -> 'live'"
}
case_fix_keeps_text() { # a bare dash note after the token, and a projection with other column names
  new_repo
  mkdir -p "$repo/topics/t1"
  printf -- '---\nstatus: held\n---\nbody\n' >"$repo/topics/t1/README.md"
  printf '| Topic | Status | Notes |\n|---|---|---|\n| [t1](t1/) | active - weekly, with the team | x |\n' >"$repo/topics/INDEX.md"
  fix_run "$1"
  [ "$rc" -eq 0 ] && grep -qF '| [t1](t1/) | held - weekly, with the team | x |' "$repo/topics/INDEX.md"
}
case_fix_store_untouched() {
  new_repo
  printf '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | retired | 2026-01-01 |\n| [gone](gone/) | live | 2026-01-02 |\n' >"$repo/widgets/INDEX.md"
  local before after rows
  before="$(shasum "$repo/widgets/w1/README.md")"
  fix_run "$1"
  after="$(shasum "$repo/widgets/w1/README.md")"
  rows="$(grep -c '^| \[' "$repo/widgets/INDEX.md")"
  [ "$rc" -eq 0 ] && [ "$before" = "$after" ] && [ "$rows" -eq 2 ] \
    && [ "$(index_line gone)" = '| [gone](gone/) | live | 2026-01-02 |' ] \
    && [ "$(index_line w1)" = '| [w1](w1/) | paused | 2026-01-01 |' ]
}
case_fix_clean_noop() {
  new_repo
  local before after
  before="$(shasum "$repo/widgets/INDEX.md" "$repo/widgets/w1/README.md")"
  fix_run "$1"
  after="$(shasum "$repo/widgets/INDEX.md" "$repo/widgets/w1/README.md")"
  [ "$rc" -eq 0 ] && [ "$before" = "$after" ] && printf '%s' "$out" | grep -q "no projection drift"
}
case_fix_then_staged_passes() {
  new_repo; put widgets/w1/README.md '---\nstatus: live\n---\nbody\n'
  fix_run "$1"
  git -C "$repo" add widgets/INDEX.md
  [ "$rc" -eq 0 ] && expect_pass "$1"
}
case_banner_names_fix() { new_repo; put widgets/w1/README.md '---\nstatus: live\n---\nbody\n'; expect_block "$1" "board state-check --fix"; }
case_prog_name() {
  new_repo; put widgets/w1/README.md '---\nstatus: live\n---\nbody\n'
  out="$(STATES_PROG="my-tool" STATES_ROOT="$repo" STATES_TOML="$tm" "$PY" "$1" --staged 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '`my-tool --fix`' && ! printf '%s' "$out" | grep -q 'board state-check'
}

# ---- registry and root arguments
case_banner_names_registry() { new_repo; put gadgets/new/gadget.toml 'status = "bogus"\n'; expect_block "$1" "BLOCKED: state registry (_meta/states.toml)"; }
case_states_file_relative() {
  new_repo; mkdir -p "$repo/conf"; mv "$repo/_meta/states.toml" "$repo/conf/own.toml"
  put gadgets/new/gadget.toml 'status = "bogus"\n'
  eng "$1" --staged --states-file conf/own.toml
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BLOCKED: state registry (conf/own.toml)" && printf '%s' "$out" | grep -q "'bogus' is not a declared state"
}
case_states_file_absolute() {
  new_repo; cp "$repo/_meta/states.toml" "$TMPD/abs-$n.toml"; rm "$repo/_meta/states.toml"
  put gadgets/new/gadget.toml 'status = "bogus"\n'
  eng "$1" --states-file "$TMPD/abs-$n.toml" --staged
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "'bogus' is not a declared state"
}
case_states_file_env() {
  new_repo; cp "$repo/_meta/states.toml" "$TMPD/env-$n.toml"; rm "$repo/_meta/states.toml"
  put gadgets/new/gadget.toml 'status = "bogus"\n'
  out="$(STATES_REGISTRY="$TMPD/env-$n.toml" STATES_ROOT="$repo" STATES_TOML="$tm" "$PY" "$1" --staged 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "'bogus' is not a declared state"
}
case_states_file_env_relative() { # a relative STATES_REGISTRY is read against the repo root, from any directory
  new_repo; mkdir -p "$repo/conf"; mv "$repo/_meta/states.toml" "$repo/conf/own.toml"
  put gadgets/new/gadget.toml 'status = "bogus"\n'
  out="$(cd "$TMPD" && env STATES_REGISTRY=conf/own.toml STATES_TOML="$tm" "$PY" "$1" --repo-root "$repo" --staged 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BLOCKED: state registry (conf/own.toml)"
}
case_repo_root_flag() { # run from an unrelated directory, name the repo by flag
  new_repo; put gadgets/new/gadget.toml 'status = "bogus"\n'
  out="$(cd "$TMPD" && env -u STATES_ROOT STATES_TOML="$tm" "$PY" "$1" --repo-root "$repo" --staged 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "'bogus' is not a declared state"
}
case_git_root_default() { # no flag, no env: the git root of the current directory, from a subdirectory
  new_repo; put gadgets/new/gadget.toml 'status = "bogus"\n'
  out="$(cd "$repo/misc" && env -u STATES_ROOT STATES_TOML="$tm" "$PY" "$1" --staged 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "'bogus' is not a declared state"
}
case_flag_beats_env() {
  new_repo; put gadgets/new/gadget.toml 'status = "bogus"\n'
  local other="$TMPD/other-$n"; mkdir -p "$other"
  out="$(STATES_ROOT="$other" STATES_TOML="$tm" "$PY" "$1" --repo-root "$repo" --staged 2>&1)"; rc=$?
  [ "$rc" -eq 1 ]
}

# ---- the --all report and the exit codes
case_all_report() {
  new_repo; put gadgets/new/gadget.toml 'status = "bogus"\n'
  git -C "$repo" add -A; git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m bogus
  eng "$1" --all
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^\[gadget\] bogus=1(UNDECLARED), closed=1, ready=1" \
    && printf '%s' "$out" | grep -q "undeclared 'bogus': 1, e.g. gadgets/new/gadget.toml" \
    && printf '%s' "$out" | grep -q "^summary: 1 undeclared value kinds and projection drift rows"
}
case_all_strict_blocks() { new_repo; put gadgets/new/gadget.toml 'status = "bogus"\n'; git -C "$repo" add -A; eng "$1" --all --strict; [ "$rc" -eq 1 ]; }
case_all_strict_clean() { new_repo; eng "$1" --all --strict; [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^summary: 0 undeclared"; }
case_all_drift_row() {
  new_repo; printf '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | live | 2026-01-01 |\n' >"$repo/widgets/INDEX.md"
  eng "$1" --all --strict
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "  drift widgets/INDEX.md: w1 says 'live', store says 'paused'"
}
case_all_malformed_row() {
  new_repo; printf '| Slug | Status | Started |\n|---|---|---|\n| [w1](w1/) | paused |\n' >"$repo/widgets/INDEX.md"
  eng "$1" --all
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "skipped malformed table row: | \[w1\](w1/) | paused |"
}
case_missing_registry_exit2() { new_repo; rm "$repo/_meta/states.toml"; eng "$1" --staged; [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "board state-check: internal error:"; }
case_bad_registry_exit2() { new_repo; printf 'check = = true\n' >"$repo/_meta/states.toml"; eng "$1" --all; [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "internal error"; }
case_no_args_usage() { new_repo; eng "$1"; [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "board state-check --all"; }
case_help_exit0() { new_repo; eng "$1" --help; [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "board state-check --staged"; }
case_flag_without_value() { new_repo; eng "$1" --all --states-file; [ "$rc" -eq 2 ]; }
case_nothing_staged() { new_repo; eng "$1" --staged; [ "$rc" -eq 0 ] && [ -z "$out" ]; }
case_verb_entry() { # the stable entry point reaches the same engine
  new_repo; put gadgets/new/gadget.toml 'status = "bogus"\n'
  out="$(cd "$repo" && env -u STATES_ROOT STATES_TOML="$tm" bash "$KIT_DIR/bin/board" state-check --staged 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "'bogus' is not a declared state"
}

case_reader_strict() { # the built-in reader agrees with tomllib on valid text and refuses text it would misread
  out="$("$PY" - "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sc_under_test", sys.argv[1])
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)
good = [
    'a = ["x\\"y", "z"]\n',
    'a = "caf\\u00e9\\r"\n',
    "a = 'lit # not a comment' # c\n",
    'a = "x # y" # c\n',
    'a = [\n "p", # one\n "q",\n]\n',
    'b = {k = "v", n = 3}\n[t.u]\nc-d = true\n"quo ted" = "z"\n',
]
bad = ['a = "x", "y"\n', 'a = "abc\\"\n', 'a = "\\q"\n', 'a = "\\u12"\n', 'a = 2026-01-01\n']
fails = []
try:
    import tomllib
except ImportError:
    tomllib = None
for doc in good:
    if tomllib is not None and sc.mini_toml_loads(doc) != tomllib.loads(doc):
        fails.append("differs: " + repr(doc))
    elif tomllib is None:
        sc.mini_toml_loads(doc)
for doc in bad:
    try:
        sc.mini_toml_loads(doc)
        fails.append("accepted: " + repr(doc))
    except sc.TomlError:
        pass
print("\n".join(fails) if fails else "OK")
PY
)"
  rc=0; [ "$out" = "OK" ]
}

check() { # name fn engine
  if "$2" "$3"; then ok "$1"; else no "$1 (rc=$rc)" "$out"; fi
}

run_rules() {
  local e="$1"
  check "undeclared new value blocks" case_undeclared "$e"
  check "legacy value on an unchanged file passes" case_legacy_unchanged "$e"
  check "newly written legacy value blocks" case_legacy_new "$e"
  check "illegal transition blocks" case_illegal_transition "$e"
  check "legal transition passes" case_legal_transition "$e"
  check "new file with a declared value passes" case_new_file_declared "$e"
  check "escape hatch passes and prints the reason" case_escape_hatch "$e"
  check "projection side drift blocks" case_drift_index_side "$e"
  check "store side drift blocks" case_drift_store_side "$e"
  check "agreeing projection and store edit passes" case_drift_agreeing_edit "$e"
  check "drift already at HEAD is grandfathered" case_drift_grandfathered "$e"
  check "edit of a past append-only row blocks" case_append_only_past_row "$e"
  check "appended row on an append-only table passes" case_append_only_append "$e"
  check "removed row on an append-only table blocks" case_append_only_removed "$e"
  check "non-matching file is ignored" case_unmatched_file "$e"
  check "prefix state matches a value with a ref" case_prefix_state "$e"
  check "table machine enforces its transitions" case_table_transition "$e"
  check "ignore_case plus body status line passes" case_ignore_case_body_status "$e"
  check "ignore_case machine still blocks an undeclared value" case_ignore_case_undeclared "$e"
  check "ignore_case transitions fold the registry's spelling too" case_ignore_case_transition_spelling "$e"
  check "unparseable store file reads as no value" case_unparseable_store "$e"
  check "store file with extra TOML still reads its status" case_store_with_extra_toml "$e"
  check "a status inside a sub-table is not read" case_store_nested_field "$e"
  check "--fix rewrites the drifted token and keeps free text" case_fix_drift "$e"
  check "--fix keeps a dash note and handles a second projection" case_fix_keeps_text "$e"
  check "--fix leaves the store and the row set alone" case_fix_store_untouched "$e"
  check "--fix is a no-op on a clean tree" case_fix_clean_noop "$e"
  check "--fix then staging passes the hook check" case_fix_then_staged_passes "$e"
  check "drift banner names the --fix command" case_banner_names_fix "$e"
  check "STATES_PROG renames the command in the hint" case_prog_name "$e"
  check "banner names the registry it read" case_banner_names_registry "$e"
  check "--states-file with a relative path" case_states_file_relative "$e"
  check "--states-file with an absolute path" case_states_file_absolute "$e"
  check "STATES_REGISTRY env names the registry" case_states_file_env "$e"
  check "a relative STATES_REGISTRY resolves against the repo root" case_states_file_env_relative "$e"
  check "--repo-root names the repo from any directory" case_repo_root_flag "$e"
  check "default root is the git root of the current directory" case_git_root_default "$e"
  check "--repo-root beats STATES_ROOT" case_flag_beats_env "$e"
  check "--all reports counts, undeclared kinds and a summary" case_all_report "$e"
  check "--all --strict exits 1 on an undeclared value" case_all_strict_blocks "$e"
  check "--all --strict exits 0 on a clean repo" case_all_strict_clean "$e"
  check "--all prints a drift row" case_all_drift_row "$e"
  check "--all reports a malformed table row" case_all_malformed_row "$e"
  check "missing registry is exit 2" case_missing_registry_exit2 "$e"
  check "unparseable registry is exit 2" case_bad_registry_exit2 "$e"
  check "no mode flag prints usage, exit 2" case_no_args_usage "$e"
  check "--help prints usage, exit 0" case_help_exit0 "$e"
  check "a flag with no value is exit 2" case_flag_without_value "$e"
  check "nothing staged is silent, exit 0" case_nothing_staged "$e"
}

echo "== Part 1: rules, native TOML reader =="
tm=""; run_rules "$ENGINE"
echo "== Part 1b: the same rules, built-in TOML reader =="
tm="mini"; run_rules "$ENGINE"

echo "== Part 2: entry point, TOML readers, importable surface, no tenant names =="
tm=""; check "bin/board state-check reaches the engine" case_verb_entry "$ENGINE"
check "built-in TOML reader matches tomllib on valid text and refuses what it would misread" case_reader_strict "$ENGINE"

mini_vs_native="$(cd "$KIT_DIR/lib/board" && "$PY" - "$FIXREG" <<'PY'
import sys
import state_check as sc
text = open(sys.argv[1]).read()
if sc.tomllib is None:
    print("SKIP no tomllib on this Python")
else:
    print("SAME" if sc.mini_toml_loads(text) == sc.tomllib.loads(text) else "DIFFERENT")
PY
)"
case "$mini_vs_native" in
  SAME) ok "built-in reader and tomllib parse the fixture registry to the same dict" ;;
  SKIP*) ok "built-in reader parity ($mini_vs_native)" ;;
  *) no "built-in reader differs from tomllib on the fixture registry" ;;
esac

surface="$(cd "$KIT_DIR/lib/board" && STATES_ROOT="$TMPD" "$PY" -c '
import pathlib, state_check as sc
need = "ROOT REGISTRY norm retoken retoken_row parse_table values move_problem classify drift glob_re cells".split()
missing = [n for n in need if not hasattr(sc, n)]
print("MISSING " + " ".join(missing) if missing else ("OK" if sc.ROOT == pathlib.Path(sc.os.environ["STATES_ROOT"]) else "ROOT-IGNORED-ENV"))
')"
[ "$surface" = "OK" ] && ok "importable: the helpers a wrapper script reuses exist and ROOT follows STATES_ROOT" || no "importable surface: $surface"

tenant_re='ops-''toolkit|ops_''toolkit|check-states|tieu''bao|family-office|airwallex'"|"'CC_[A-Z]'
leaks="$(cd "$KIT_DIR" && grep -nEI "$tenant_re" lib/board/state_check.py tests/fixtures/state-check/states.toml 2>/dev/null)"
[ -z "$leaks" ] && ok "engine and fixture registry name no tenant" || no "tenant names in the engine or fixture" "$leaks"

echo "== Part 3: negative control, break each rule once in a copy, its case must go red =="
tm="mini"
mutate() { # name case_fn from to
  local broken="$TMPD/broken-$1.py"
  FROM="$3" TO="$4" "$PY" - "$ENGINE" "$broken" <<'PY'
import os, sys
src = open(sys.argv[1]).read()
if os.environ["FROM"] not in src:
    sys.exit("mutation target missing: " + os.environ["FROM"])
open(sys.argv[2], "w").write(src.replace(os.environ["FROM"], os.environ["TO"], 1))
PY
  if [ $? -ne 0 ]; then no "mutation '$1' does not apply to the engine"; return; fi
  if "$2" "$broken"; then no "'$1' case stayed green with its rule removed (toothless)"; else ok "'$1' case goes red when its rule is removed"; fi
}
mutate undeclared case_undeclared 'if kind == "undeclared":
        return' 'if False:
        return'
mutate legacy case_legacy_new 'if kind == "legacy":
        return' 'if False:
        return'
mutate transition case_illegal_transition 'if fold(new) not in {fold(s) for s in allowed}:' 'if False:'
mutate transition-fold case_ignore_case_transition_spelling '        fold = (lambda s: s.lower()) if m.get("ignore_case") else (lambda s: s)' '        fold = (lambda s: s)'
mutate drift-projection case_drift_index_side 'if (f, key, got, want) not in drift(m, read_head, {path}):' 'if False:'
mutate drift-store case_drift_store_side 'if (f, key, got, want) not in drift(m, read_head, {path}):' 'if False:'
mutate grandfather-drift case_drift_grandfathered 'if (f, key, got, want) not in drift(m, read_head, {path}):' 'if True:'
mutate append-only case_append_only_past_row 'if m.get("append_only") and old_entry:' 'if False:'
mutate append-only-removed case_append_only_removed 'problems += [f"{k} [{name}]: past row removed (append-only)" for k in old_vals.keys() - new_vals.keys()]' 'pass'
mutate escape-hatch case_escape_hatch 'reason = os.environ.get("ALLOW_STATE_CHANGE")' 'reason = None'
mutate fix-rewrite case_fix_drift 'lines[at] = "|".join(parts)' 'lines[at] = row'
mutate fix-keeps-text case_fix_keeps_text '{m2.group(1)}{want}{m2.group(3)}"' '{m2.group(1)}{want}"'
mutate fix-banner case_banner_names_fix '`{PROG} --fix`' '`{PROG} --nothing`'
mutate fix-store-only case_fix_store_untouched 'for f, key, got, want in sorted(drift(m, read_disk)):
            proj' 'for f, key, got, want in sorted(drift(m, read_disk)):
            (ROOT / m["glob"].replace("*", key, 1)).write_text("---\nstatus: " + got + "\n---\n")
            proj'
mutate block-exit case_undeclared 'return 1
' 'return 0
'
mutate states-file case_states_file_relative '    if registry:
        REGISTRY = ROOT / registry' '    if registry:
        pass'
mutate repo-root case_repo_root_flag '        ROOT = Path(root)' '        pass'
mutate git-root case_git_root_default 'return Path(top.stdout.strip() if top.returncode == 0 and top.stdout.strip() else os.getcwd())' 'return Path(os.getcwd())'
mutate registry-label case_banner_names_registry 'f"BLOCKED: state registry ({registry_label()})"' '"BLOCKED: state registry (x)"'
mutate prog-name case_prog_name 'PROG = os.environ.get("STATES_PROG") or "board state-check"' 'PROG = "board state-check"'
mutate strict-exit case_all_strict_blocks 'return 1 if strict and bad else 0' 'return 0'
mutate mini-table-nesting case_illegal_transition 'cur = cur.setdefault(_key(part), {})' 'cur = root.setdefault(_key(part), {})'
mutate reader-closing-quote case_reader_strict '            if i != len(raw) - 1:
                raise TomlError(f"text after a string: {raw[:30]}")' '            if False:
                raise TomlError("x")'
mutate mini-top-value case_store_nested_field '        if line.startswith("["):
            return None' '        if False:
            return None'

echo ""
echo "== $((PASS + FAIL)) run, $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
