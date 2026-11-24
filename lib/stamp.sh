#!/usr/bin/env bash
# kit-verb: stamp | write a kit-free agent harness into a repo as plain files the repo owns, idempotent, never overwriting an edited file
# stamp.sh -- render the team-stamp templates into a target repo.
#
# The files it writes run with no kit installed: the repo owns them after the write. This script
# is the only kit-side part. It reads templates/team-stamp/manifest.d/*.tsv (one file per build
# group), renders each row with a small value set, and writes only what is absent. A file the repo
# edited is never touched. What it wrote is recorded in <target>/.claude/team-stamp.lock (plain
# text, kit-free): the values used and one sha256:<hex> per file, so "the repo edited this" can be told
# from "this is an older stamp copy".
#
# Usage: stamp.sh [--check | --dry-run | --refresh | --take <path>] [--only <group,group>]
#                 [--default-branch B] [--owner LOGIN] [--tags a,b] [--product-paths a/,b/]
#                 [--door-paths p,q] [--door-approver LOGIN] [--board-file P] [--decision-tag T]
#                 [--] <target-dir>
#   (none)     write every missing file, merge .claude/settings.json, update the lock; print one
#              status line per file: created, unchanged, edited (left alone), older stamp
#              (run --refresh), missing, merged. A `seed` or `hook` row is created when absent and
#              never drift-checked after (OWNERS.md, CHANGELOG.md and the like live in the repo).
#   --check    write nothing; exit 0 only when every file is present and unchanged.
#   --dry-run  write nothing; print what would be written.
#   --refresh  write nothing; print, per older-stamp file, a unified diff and the --take command.
#   --take P   replace exactly one file P that the repo did not edit (its hash equals its lock hash),
#              keeping the old content in P.orig. An edited file is refused and its diff printed.
#   --only     restrict the run to the named manifest groups (a group test uses it).
# Values: a flag wins, else the lock's, else the default. Exit 0 ok, 1 refused or drift (--check),
# 64 usage. A refusal prints two lines: "stamp: <rule>" then "Fix: <command>".
# Env: STAMP_TEMPLATES overrides the templates root (tests use a fixture tree).
# The derived values are read through ${!k} when the values file is written.
# shellcheck disable=SC2034
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SELF_DIR/.." && pwd)"
TPL_ROOT="${STAMP_TEMPLATES:-$SRC_ROOT/templates/team-stamp}"
STAMP_VERSION=1
LOCK_REL=".claude/team-stamp.lock"
BASE_KEYS="DEFAULT_BRANCH OWNER TAGS PRODUCT_PATHS DOOR_PATHS DOOR_APPROVER BOARD_FILE DECISION_TAG"
DERIVED_KEYS="TAGS_ERE TAGS_COLON TAGS_AWK PRODUCT_ERE PRODUCT_ARRAY DOOR_ARRAY DOOR_CASE"
KNOWN_KEYS="$BASE_KEYS $DERIVED_KEYS STAMP_VERSION KIT_MARKER"
# Text a generated file must not carry: a path under the kit, or an absolute home path.
KIT_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'

STAGE=""
trap '[ -z "$STAGE" ] || rm -rf "$STAGE"' EXIT

usage() {
  echo "usage: stamp.sh [--check | --dry-run | --refresh | --take <path>] [--only <groups>] [--default-branch B] [--owner LOGIN] [--tags a,b] [--product-paths a/,b/] [--door-paths p,q] [--door-approver LOGIN] [--board-file P] [--decision-tag T] [--] <target-dir>" >&2
  exit 64
}
refuse() { printf 'stamp: %s\nFix: %s\n' "$1" "$2" >&2; exit 1; }

sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1"; else shasum -a 256 < "$1"; fi | cut -d' ' -f1; }
diff_lines() { diff "$1" "$2" | grep -c '^[<>]'; }

MODE=write TAKE_PATH="" ONLY=""
F_DEFAULT_BRANCH="" F_OWNER="" F_TAGS="" F_PRODUCT_PATHS="" F_DOOR_PATHS="" F_DOOR_APPROVER="" F_BOARD_FILE="" F_DECISION_TAG=""
setmode() { [ "$MODE" = write ] || usage; MODE="$1"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --check) setmode check; shift;;
    --dry-run) setmode dry; shift;;
    --refresh) setmode refresh; shift;;
    --take) setmode take; shift; TAKE_PATH="${1:-}"; [ -n "$TAKE_PATH" ] || usage; shift;;
    --only) shift; ONLY="${1:-}"; [ -n "$ONLY" ] || usage; shift;;
    --default-branch) shift; F_DEFAULT_BRANCH="${1:-}"; [ -n "$F_DEFAULT_BRANCH" ] || usage; shift;;
    --owner) shift; F_OWNER="${1:-}"; [ -n "$F_OWNER" ] || usage; shift;;
    --tags) shift; F_TAGS="${1:-}"; [ -n "$F_TAGS" ] || usage; shift;;
    --product-paths) shift; F_PRODUCT_PATHS="${1:-}"; [ -n "$F_PRODUCT_PATHS" ] || usage; shift;;
    --door-paths) shift; F_DOOR_PATHS="${1:-}"; [ -n "$F_DOOR_PATHS" ] || usage; shift;;
    --door-approver) shift; F_DOOR_APPROVER="${1:-}"; [ -n "$F_DOOR_APPROVER" ] || usage; shift;;
    --board-file) shift; F_BOARD_FILE="${1:-}"; [ -n "$F_BOARD_FILE" ] || usage; shift;;
    --decision-tag) shift; F_DECISION_TAG="${1:-}"; [ -n "$F_DECISION_TAG" ] || usage; shift;;
    --) shift; break;;
    -*) usage;;
    *) break;;
  esac
done
TARGET="${1:-}"; [ -n "$TARGET" ] || usage
[ $# -le 1 ] || usage
[ -d "$TARGET" ] || refuse "target dir not found: $TARGET" "pass an existing repo directory"
TARGET="$(cd "$TARGET" && pwd)"
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
  || refuse "$TARGET is not a git repo; the default branch and the hook need one" "git init $TARGET"
target_real="$(cd "$TARGET" && pwd -P)"
for kit_dir in "$SRC_ROOT" "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}"; do
  [ -d "$kit_dir" ] && [ "$target_real" = "$(cd "$kit_dir" && pwd -P)" ] \
    && refuse "refusing to stamp the kit's own tree: $TARGET" "pass the repo you want to stamp"
done

LOCK="$TARGET/$LOCK_REL"
lock_has() { [ -f "$LOCK" ] && awk -v p="$1" '$1=="file" && $2==p {f=1} END{exit !f}' "$LOCK"; }
# A lock hash is written as sha256:<hex> so a secret scan reads it as a digest; an older bare hex still reads.
lock_hash() { [ -f "$LOCK" ] && awk -v p="$1" '$1=="file" && $2==p {sub(/^sha256:/, "", $4); print $4; exit}' "$LOCK"; }
lock_value() { [ -f "$LOCK" ] && awk -v k="$1" '$1=="value" && $2==k {print $3; exit}' "$LOCK"; }

# ---- values: flag, else lock, else default ----
pick() { # pick KEY FLAGVALUE DEFAULT
  local l
  if [ -n "$2" ]; then printf '%s' "$2"; return; fi
  l="$(lock_value "$1")"
  if [ -n "$l" ]; then printf '%s' "$l"; else printf '%s' "$3"; fi
}
v_login() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]*$'; }
v_list() { # comma list of path-ish items, no spaces or shell quoting
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._@/*-]+(,[A-Za-z0-9._@/*-]+)*$'
}

DEFAULT_BRANCH="$(pick DEFAULT_BRANCH "$F_DEFAULT_BRANCH" "")"
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="$(git -C "$TARGET" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
fi
OWNER="$(pick OWNER "$F_OWNER" "")"
TAGS="$(pick TAGS "$F_TAGS" "product,dev")"
PRODUCT_PATHS="$(pick PRODUCT_PATHS "$F_PRODUCT_PATHS" "src/")"
DOOR_PATHS="$(pick DOOR_PATHS "$F_DOOR_PATHS" "")"
DOOR_APPROVER="$(pick DOOR_APPROVER "$F_DOOR_APPROVER" "")"
BOARD_FILE="$(pick BOARD_FILE "$F_BOARD_FILE" "")"
DECISION_TAG="$(pick DECISION_TAG "$F_DECISION_TAG" "decision")"

[ -z "$DEFAULT_BRANCH" ] || printf '%s' "$DEFAULT_BRANCH" | grep -Eq '^[A-Za-z0-9._/-]+$' \
  || refuse "bad --default-branch '$DEFAULT_BRANCH'" "pass a plain branch name such as main"
[ -z "$OWNER" ] || v_login "$OWNER" || refuse "bad --owner '$OWNER': a GitHub login has no @ and no spaces" "pass --owner <login>"
[ -z "$DOOR_APPROVER" ] || v_login "$DOOR_APPROVER" || refuse "bad --door-approver '$DOOR_APPROVER'" "pass --door-approver <login>"
printf '%s' "$TAGS" | grep -Eq '^[a-z][a-z0-9-]*(,[a-z][a-z0-9-]*)*$' || refuse "bad --tags '$TAGS': lowercase words joined by commas" "pass --tags product,dev"
case ",$TAGS," in *,dev,*) ;; *) TAGS="$TAGS,dev";; esac
v_list "$PRODUCT_PATHS" || refuse "bad --product-paths '$PRODUCT_PATHS'" "pass --product-paths src/,lib/"
[ -z "$DOOR_PATHS" ] || v_list "$DOOR_PATHS" || refuse "bad --door-paths '$DOOR_PATHS'" "pass --door-paths docs/legal/*,protocol/*"
[ -z "$BOARD_FILE" ] || v_list "$BOARD_FILE" || refuse "bad --board-file '$BOARD_FILE'" "pass a repo-relative path"
printf '%s' "$DECISION_TAG" | grep -Eq '^[a-z][a-z0-9-]*$' || refuse "bad --decision-tag '$DECISION_TAG'" "pass a lowercase word such as decision"

quote_list() { # quote_list a,b -> "a" "b" (shell array body); empty in, empty out
  printf '%s' "$1" | awk -F, 'NF && $1 != "" {for(i=1;i<=NF;i++) printf "%s\"%s\"", (i>1?" ":""), $i}'
}
TAGS_ERE="$(printf '%s' "$TAGS" | tr ',' '|')"
TAGS_COLON="$(printf '%s' "$TAGS" | awk -F, '{for(i=1;i<=NF;i++) printf "%s%s:", (i>1?" ":""), $i}')"
TAGS_AWK="$(printf '%s' "$TAGS" | awk -F, '{for(i=1;i<=NF;i++) printf "%s\"%s\"", (i>1?", ":""), $i}')"
PRODUCT_ERE="^($(printf '%s' "$PRODUCT_PATHS" | sed 's/[.]/\\./g' | tr ',' '|'))"
PRODUCT_ARRAY="$(quote_list "$PRODUCT_PATHS")"
DOOR_ARRAY="$(quote_list "$DOOR_PATHS")"
if [ -n "$DOOR_PATHS" ]; then DOOR_CASE="$(printf '%s' "$DOOR_PATHS" | tr ',' '|')"; else DOOR_CASE=".stamp-no-door-path"; fi

# ---- manifest: manifest.d/NN-<group>.tsv, five tab-separated columns ----
ACT=(); SRC=(); TGT=(); MOD=(); KEY=(); GRP=()
n=0; seen_groups=" "; seen_targets=" "
ALL_TARGETS=""   # every target of every group, whatever --only selected
mf_refuse() { refuse "$1 ($2)" "fix the row in $2"; }
shopt -s nullglob
for mf in "$TPL_ROOT"/manifest.d/*.tsv; do
  g="$(basename "$mf" .tsv | sed -E 's/^[0-9]+-//')"
  skip=0
  if [ -n "$ONLY" ]; then case ",$ONLY," in *",$g,"*) ;; *) skip=1;; esac; fi
  [ "$skip" -eq 1 ] || seen_groups="$seen_groups$g "
  while IFS=$'\t' read -r a s t m k rest || [ -n "$a" ]; do
    case "$a" in ''|'#'*) continue;; esac
    [ -z "$rest" ] || mf_refuse "a manifest row has more than five columns" "$mf"
    case "$a" in copy|seed|jsonmerge|hook) ;; *) mf_refuse "unknown action '$a'" "$mf";; esac
    printf '%s' "$t" | grep -Eq '^[A-Za-z0-9_@.][A-Za-z0-9._@-]*(/[A-Za-z0-9._@-]+)*$' || mf_refuse "bad target '$t'" "$mf"
    case "/$t/" in */../*|*/./*) mf_refuse "bad target '$t'" "$mf";; esac
    printf '%s' "$m" | grep -Eq '^[0-7]{3,4}$' || mf_refuse "bad mode '$m' for $t" "$mf"
    [ -n "$k" ] || mf_refuse "empty keys column for $t (write - for none)" "$mf"
    case "$seen_targets" in *" $t "*) mf_refuse "target $t is listed twice" "$mf";; esac
    seen_targets="$seen_targets$t "
    ALL_TARGETS="$ALL_TARGETS$t
"
    [ "$skip" -eq 0 ] || continue
    if [ "$a" = hook ]; then
      case "$s" in lib/*) gsrc="$SRC_ROOT/$s";; *) gsrc="$TPL_ROOT/$s";; esac
      [ -f "$gsrc" ] || mf_refuse "hook script not found: $s" "$mf"
      SRC[n]="$gsrc"
    else
      [ -f "$TPL_ROOT/$s" ] || mf_refuse "template not found: $s" "$mf"
      SRC[n]="$TPL_ROOT/$s"
    fi
    ACT[n]="$a"; TGT[n]="$t"; MOD[n]="$m"; KEY[n]="$k"; GRP[n]="$g"
    n=$((n + 1))
  done < "$mf"
done
shopt -u nullglob
if [ -n "$ONLY" ]; then
  for g in $(printf '%s' "$ONLY" | tr ',' ' '); do
    case "$seen_groups" in *" $g "*) ;; *) refuse "no manifest group named '$g'" "list groups with: ls $TPL_ROOT/manifest.d";; esac
  done
fi
[ "$n" -gt 0 ] || refuse "no manifest rows under $TPL_ROOT/manifest.d" "add a manifest.d/NN-<group>.tsv"

# ---- symlink guard over every path the run reads or writes ----
# shellcheck source=lib/config/safe-path.sh
source "$SELF_DIR/config/safe-path.sh" || refuse "safe-path.sh missing" "restore lib/config/safe-path.sh"
guard_paths=("$LOCK")
i=0; while [ "$i" -lt "$n" ]; do guard_paths+=("$TARGET/${TGT[i]}" "$TARGET/${TGT[i]}.orig"); i=$((i + 1)); done
guard_msg="$(kit_refuse_symlink_path "$TARGET" "${guard_paths[@]}" 2>&1)" \
  || refuse "$(printf '%s' "$guard_msg" | head -n 1); nothing was written" "replace the symlink with a regular path, or stamp a different repo"

# ---- required keys ----
need_key() { # need_key KEY: does any selected row declare it
  local j=0; while [ "$j" -lt "$n" ]; do case ",${KEY[j]}," in *",$1,"*) return 0;; esac; j=$((j + 1)); done; return 1
}
i=0; while [ "$i" -lt "$n" ]; do
  for k in $(printf '%s' "${KEY[i]}" | tr ',' ' '); do
    [ "$k" = "-" ] && continue
    case " $KNOWN_KEYS " in *" $k "*) ;; *) refuse "${TGT[i]} declares the unknown key $k" "use one of: $KNOWN_KEYS";; esac
  done
  i=$((i + 1))
done
if need_key DEFAULT_BRANCH && [ -z "$DEFAULT_BRANCH" ]; then
  refuse "no default branch: this repo has no origin/HEAD and no --default-branch was given" "bash lib/stamp.sh --default-branch main $TARGET"
fi
if need_key OWNER && [ -z "$OWNER" ]; then
  refuse "no owner: OWNERS.md needs one login" "bash lib/stamp.sh --owner <github-login> $TARGET"
fi
KIT_MARKER=""
if need_key KIT_MARKER; then
  KIT_MARKER="$(head -n 1 "$SRC_ROOT/lib/adopt/AGENTS.pointer.md" 2>/dev/null | tr -d '\r')"
  case "$KIT_MARKER" in "<!-- kit:agents-pointer"*) ;; *) refuse "line 1 of lib/adopt/AGENTS.pointer.md is not the kit marker" "restore lib/adopt/AGENTS.pointer.md";; esac
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/stamp.XXXXXX")" || exit 1
VALUES="$STAGE/values.tsv"
{
  for k in $KNOWN_KEYS; do
    case "$k" in STAMP_VERSION) v="$STAMP_VERSION";; *) v="${!k}";; esac
    printf '%s\t%s\n' "$k" "$v"
  done
} > "$VALUES"

render() { # render <template> -> stdout
  awk -F'\t' '
    FNR == NR { v[$1] = $2; next }
    { line = $0; out = ""
      while ((i = index(line, "{{")) > 0) {
        rest = substr(line, i + 2); j = index(rest, "}}")
        if (j == 0) break
        k = substr(rest, 1, j - 1)
        if (k in v) { out = out substr(line, 1, i - 1) v[k]; line = substr(rest, j + 2) }
        else { out = out substr(line, 1, i + 1); line = rest }
      }
      print out line }' "$VALUES" "$1"
}

# ---- plan: render every row into the stage, check it, decide its status ----
ST=(); DET=()
TARGETS_FILE="$STAGE/targets.txt"; ALL_TARGETS_FILE="$STAGE/all-targets.txt"
i=0; while [ "$i" -lt "$n" ]; do printf '%s\n' "${TGT[i]}"; i=$((i + 1)); done > "$TARGETS_FILE"
printf '%s' "$ALL_TARGETS" > "$ALL_TARGETS_FILE"

stage_row() { # stage_row i: leave the new content of row i in $STAGE/r<i>
  local i="$1" used k out="$STAGE/r$1"
  case "${ACT[i]}" in
    hook)
      ( cd "$TARGET" && STAMP_TARGETS_FILE="$TARGETS_FILE" STAMP_ALL_TARGETS_FILE="$ALL_TARGETS_FILE" STAMP_VALUES_FILE="$VALUES" bash "${SRC[i]}" "$TARGET" ) > "$out" 2>"$STAGE/err" \
        || refuse "hook for ${TGT[i]} failed: $(head -n 1 "$STAGE/err")" "run the generator by hand: bash ${SRC[i]} $TARGET";;
    *)
      used="$(grep -o '{{[A-Za-z_][A-Za-z0-9_]*}}' "${SRC[i]}" | tr -d '{}' | sort -u)"
      for k in $used; do
        case ",${KEY[i]}," in *",$k,"*) ;; *) refuse "template for ${TGT[i]} uses {{$k}} but its manifest row does not declare it" "add $k to the keys column of the row for ${TGT[i]}";; esac
      done
      render "${SRC[i]}" > "$out";;
  esac
  if grep -Eq '\{\{[A-Za-z_][A-Za-z0-9_]*\}\}' "$out"; then
    refuse "${TGT[i]} still holds an unresolved {{KEY}} after the render" "use only these keys: $KNOWN_KEYS"
  fi
  if grep -Eq "$KIT_PATTERN" "$out" || { [ -n "${HOME:-}" ] && [ "${#HOME}" -gt 1 ] && grep -qF "$HOME" "$out"; }; then
    refuse "${TGT[i]} would carry a path under the kit or an absolute home path: $(grep -En "$KIT_PATTERN" "$out" | head -n 1 | cut -c1-80)" "remove that text from the template; generated files must run with no kit"
  fi
}

merge_json() { # merge_json i: write the merged settings JSON to $STAGE/m<i>
  local i="$1" cur base
  cur="$TARGET/${TGT[i]}"; base="$STAGE/base$1.json"
  command -v jq >/dev/null 2>&1 || refuse "jq is needed to merge ${TGT[i]}" "install jq, then re-run"
  if [ -f "$cur" ]; then
    jq -e 'type == "object"' "$cur" >/dev/null 2>&1 || refuse "${TGT[i]} is not a JSON object; nothing was written" "fix ${TGT[i]} by hand, then re-run"
    cp "$cur" "$base"
  else
    echo '{}' > "$base"
  fi
  jq --slurpfile tpl "$STAGE/r$i" '
    def addhooks($new): . as $grp | ($grp.hooks // []) as $have
      | $grp | .hooks = ($have + [ $new[] | select(.command as $c | ($have | map(.command) | index($c)) == null) ]);
    def mergegroups($new): reduce $new[] as $g (.;
      (map(.matcher // "") | index($g.matcher // "")) as $ix
      | if $ix == null then . + [$g] else .[$ix] |= addhooks($g.hooks) end);
    .hooks = ((.hooks // {}) as $h
      | reduce (($tpl[0].hooks // {}) | to_entries[]) as $e ($h; .[$e.key] = ((.[$e.key] // []) | mergegroups($e.value))))
  ' "$base" > "$STAGE/m$i" || refuse "could not merge ${TGT[i]}" "fix ${TGT[i]} by hand, then re-run"
}

# copy rows first, then hook rows (a hook reads the target lists only)
i=0; while [ "$i" -lt "$n" ]; do [ "${ACT[i]}" = hook ] || stage_row "$i"; i=$((i + 1)); done
i=0; while [ "$i" -lt "$n" ]; do [ "${ACT[i]}" != hook ] || stage_row "$i"; i=$((i + 1)); done

i=0; while [ "$i" -lt "$n" ]; do
  t="$TARGET/${TGT[i]}"; new="$STAGE/r$i"; ST[i]=""; DET[i]=""
  if [ "${ACT[i]}" = jsonmerge ]; then
    merge_json "$i"
    if [ ! -e "$t" ]; then ST[i]=merge
    elif [ "$(jq -cS . "$t")" = "$(jq -cS . "$STAGE/m$i")" ]; then ST[i]=unchanged
    else ST[i]=merge; fi
  elif [ "${ACT[i]}" = seed ] || [ "${ACT[i]}" = hook ]; then
    if [ -e "$t" ]; then ST[i]=unchanged; else ST[i]=create; fi
  elif [ ! -e "$t" ]; then
    if lock_has "${TGT[i]}"; then ST[i]=missing; else ST[i]=create; fi
  else
    cur="$(sha256_of "$t")"; rend="$(sha256_of "$new")"
    if lock_has "${TGT[i]}"; then
      if [ "$cur" = "$(lock_hash "${TGT[i]}")" ]; then
        if [ "$cur" = "$rend" ]; then ST[i]=unchanged; else ST[i]=older; fi
      else ST[i]=edited; DET[i]="$(diff_lines "$t" "$new") lines differ"; fi
    elif [ "$cur" = "$rend" ]; then ST[i]=unchanged;
    else ST[i]=edited; DET[i]="not written by stamp, $(diff_lines "$t" "$new") lines differ"; fi
  fi
  i=$((i + 1))
done

say() { # say STATUS PATH [detail]
  if [ -n "${3:-}" ]; then printf '%s: %s (%s)\n' "$1" "$2" "$3"; else printf '%s: %s\n' "$1" "$2"; fi
}

report() { # report: one status line per row for the current mode
  local i=0 s
  while [ "$i" -lt "$n" ]; do
    s="${ST[i]}"
    case "$s" in
      unchanged) say unchanged "${TGT[i]}";;
      create) case "$MODE" in dry) say "would create" "${TGT[i]}";; check|refresh) say missing "${TGT[i]}";; *) say created "${TGT[i]}";; esac;;
      merge) case "$MODE" in dry) say "would merge" "${TGT[i]}";; check|refresh) say missing "${TGT[i]}" "settings entries absent";; *) say merged "${TGT[i]}";; esac;;
      missing) say missing "${TGT[i]}" "the lock lists it; not re-created";;
      edited) say "edited (left alone)" "${TGT[i]}" "${DET[i]}";;
      older) say "older stamp (run --refresh)" "${TGT[i]}";;
    esac
    i=$((i + 1))
  done
}

row_of() { # row_of path -> index or empty
  local i=0; while [ "$i" -lt "$n" ]; do [ "${TGT[i]}" = "$1" ] && { echo "$i"; return; }; i=$((i + 1)); done
}

write_row() { # write_row i: atomic write of the staged content, mode from the manifest
  local i="$1" t src tmp
  t="$TARGET/${TGT[i]}"
  src="$STAGE/r$i"; [ "${ACT[i]}" = jsonmerge ] && src="$STAGE/m$i"
  mkdir -p "$(dirname "$t")" || exit 1
  tmp="$(mktemp "$(dirname "$t")/.stamp.XXXXXX")" || exit 1
  cp "$src" "$tmp" && chmod "${MOD[i]}" "$tmp" && mv "$tmp" "$t" \
    || { rm -f "$tmp"; echo "stamp: failed to write $t" >&2; exit 1; }
}

LOCK_UPDATES="$STAGE/lock-updates.txt"; : > "$LOCK_UPDATES"
note_lock() { printf 'file %s %s sha256:%s\n' "${TGT[$1]}" "${GRP[$1]}" "$(sha256_of "$TARGET/${TGT[$1]}")" >> "$LOCK_UPDATES"; }

write_lock() {
  local new="$STAGE/lock.new" k v
  {
    echo "stamp-version $STAMP_VERSION"
    for k in $BASE_KEYS; do v="${!k}"; printf 'value %s %s\n' "$k" "$v"; done
    { [ -f "$LOCK" ] && grep '^file ' "$LOCK"; cat "$LOCK_UPDATES"; } | awk '{ last[$2] = $0 } END { for (p in last) print last[p] }' | LC_ALL=C sort -k2
  } > "$new"
  if [ -f "$LOCK" ] && cmp -s "$new" "$LOCK"; then return 0; fi
  mkdir -p "$(dirname "$LOCK")" || exit 1
  local tmp; tmp="$(mktemp "$(dirname "$LOCK")/.stamp.XXXXXX")" || exit 1
  cp "$new" "$tmp" && chmod 0644 "$tmp" && mv "$tmp" "$LOCK" || { rm -f "$tmp"; echo "stamp: failed to write the lock" >&2; exit 1; }
}

is_known_kit_file() { # is_known_kit_file <file>: adopt's own pointer, an old kit copy, or adopt's proof marker
  local f="$1" h
  h="$(sha256_of "$f")"
  [ "$h" = "$(sha256_of "$SRC_ROOT/lib/adopt/AGENTS.pointer.md" 2>/dev/null)" ] && return 0
  grep -q "^$h " "$SRC_ROOT/lib/adopt/agents-known.sha256" 2>/dev/null && return 0
  [ "$(head -n 1 "$f" | tr -d '\r')" = "# Verification (proof-of-done marker)" ] && [ "$(grep -c '' "$f")" -le 8 ]
}

interplay_notes() { # lines only a reader of adopt's files can write; returns 1 when one is a drift line
  local rc=0 k="$TARGET/.kit.toml" sj="$TARGET/.claude/settings.json" c
  if [ -n "$(row_of .kit.toml)" ] && [ -f "$k" ] && grep -Eq '^[[:space:]]*lane_gates[[:space:]]*=[[:space:]]*true' "$k"; then
    printf 'stamp: .kit.toml sets lane_gates = true; a team repo runs with it off\nFix: set lane_gates = false in .kit.toml\n'
    rc=1
  fi
  if [ -f "$sj" ] && command -v jq >/dev/null 2>&1; then
    c="$(jq '[ (.hooks // {}) | .[] | .[] | (.hooks // [])[] | (.command // "") | select(contains("dwarves-kit")) ] | length' "$sj" 2>/dev/null)"
    [ "${c:-0}" -gt 0 ] && printf 'note: .claude/settings.json holds %s kit hook command(s); the stamp leaves them in place\n' "$c"
  fi
  return $rc
}

drift=0
case "$MODE" in
  check|dry|refresh)
    report
    interplay_notes || [ "$MODE" != check ] || drift=1
    if [ "$MODE" = refresh ]; then
      i=0; while [ "$i" -lt "$n" ]; do
        if [ "${ST[i]}" = older ]; then
          echo "--- ${TGT[i]} (current, as stamped)"; echo "+++ ${TGT[i]} (new template)"
          diff -u "$TARGET/${TGT[i]}" "$STAGE/r$i" | tail -n +3
          echo "Fix: bash lib/stamp.sh --take ${TGT[i]} $TARGET"
        fi
        i=$((i + 1))
      done
    fi
    if [ "$MODE" = check ]; then
      i=0; while [ "$i" -lt "$n" ]; do [ "${ST[i]}" = unchanged ] || drift=1; i=$((i + 1)); done
    fi
    exit "$drift";;
  take)
    p="${TAKE_PATH#./}"; ix="$(row_of "$p")"
    [ -n "$ix" ] || refuse "$p is not a stamped file" "pick one of: $(tr '\n' ' ' < "$TARGETS_FILE")"
    [ "${ACT[ix]}" != jsonmerge ] || refuse "$p is merged into, never replaced" "edit $p by hand"
    case "${ACT[ix]}" in seed|hook) refuse "$p is seeded once and then belongs to the repo" "edit $p by hand";; esac
    t="$TARGET/$p"
    [ -f "$t" ] || refuse "$p is not present" "bash lib/stamp.sh $TARGET"
    cur="$(sha256_of "$t")"; rend="$(sha256_of "$STAGE/r$ix")"
    if [ "$cur" = "$rend" ]; then say unchanged "$p"; note_lock "$ix"; write_lock; exit 0; fi
    ok=0
    if lock_has "$p"; then [ "$cur" = "$(lock_hash "$p")" ] && ok=1
    else is_known_kit_file "$t" && ok=1; fi
    if [ "$ok" -ne 1 ]; then
      echo "--- $p (current, includes the repo's edits)"; echo "+++ $p (new template)"
      diff -u "$t" "$STAGE/r$ix" | tail -n +3
      refuse "$p was edited, so the stamp does not replace it" "apply the diff above by hand"
    fi
    bak="$t.orig"; [ ! -e "$bak" ] || { c=1; while [ -e "$bak.$c" ]; do c=$((c + 1)); done; bak="$bak.$c"; }
    cp -p "$t" "$bak" || exit 1
    write_row "$ix"; note_lock "$ix"; write_lock
    say replaced "$p" "old copy kept as ${bak#"$TARGET"/}"
    exit 0;;
esac

# default write run
i=0; while [ "$i" -lt "$n" ]; do
  case "${ST[i]}" in
    create|merge) write_row "$i"; note_lock "$i";;
    unchanged) case "${ACT[i]}" in seed|hook) ;; *) note_lock "$i";; esac;;
  esac
  i=$((i + 1))
done
report
interplay_notes || true
write_lock
exit 0
