#!/usr/bin/env bash
# feature-registry.sh -- deterministic feature-inventory generator.
#
# Scans the four live feature kinds (commands/*.md, agents/*.md, skills/*/SKILL.md,
# hooks/*.sh) plus the user-facing lib verbs that declare themselves, and emits docs/FEATURES.md as a GENERATED projection: one table per
# kind, one row per feature, carrying trigger class, description, spec refs, and
# test refs. Pure bash + grep/sed/awk/jq (all already required by tests/).
#
# Deterministic by construction: LC_ALL=C, sorted globs, no timestamps in the
# output -- tests/test-meta.sh pins freshness by regenerating to a temp file and
# diffing against the committed docs/FEATURES.md, so any nondeterministic byte
# would be a permanent RED.
#
# Trigger classes (derivation rules, no judgment):
#   [H]   command/skill with frontmatter `disable-model-invocation: true`
#   [H/I] any other command
#   [I]   any other skill
#   [E]   hook; event(s) looked up in hooks/hooks.json (statusline.sh rides the
#         settings.json statusLine key); wired nowhere -> event `-`
#   [D]   agent; dispatched-by derived by token-grepping commands/*.md and
#         skills/*/SKILL.md (skill dispatchers marked `(skill)`)
#   [V]   lib verb; declared by a header line in the script that owns it, within its first
#         40 lines: `# kit-verb: <name> | <one-line description>` (a script may carry several).
#         A verb with no marker is not listed; delete the marker and the row disappears.
#
# `generate` also syncs the hand-maintained count strings in README.md and
# docs/architecture.md (agents/commands/skills/hooks totals) so nobody has to
# recompute and hand-edit them when a feature is added or removed; the
# corresponding tests/test-meta.sh assertions become drift detectors, not a
# manual-arithmetic chore.
#
# Usage:
#   feature-registry.sh generate [outfile]   # default: docs/FEATURES.md
#   feature-registry.sh check [--fix] [outfile]

set -euo pipefail
export LC_ALL=C

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# frontmatter field: first `key: value` line inside the first --- pair
fm_field() { # <file> <key>
  awk -v k="$2" '
    /^---$/ { c++; next }
    c == 1 && index($0, k ":") == 1 { sub("^" k ":[[:space:]]*", ""); print; exit }
    c >= 2 { exit }' "$1"
}

# escape pipes and clip to one table-safe line
clip() { # <text>
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  s="${s//|/\\|}"
  if [ "${#s}" -gt 140 ]; then printf '%s…' "${s:0:139}"; else printf '%s' "$s"; fi
}

# exact-token pattern: hyphens are part of the token, so `review` never matches
# inside `review-team`
token_pat() { printf '(^|[^A-Za-z0-9_-])%s([^A-Za-z0-9_-]|$)' "$1"; }

# Tests live in tests/*.sh and in per-lib suites (lib/*/tests/**, shell and Python; fixtures
# are inputs, not tests). A lib verb also counts a test that names a hook which calls it.
TEST_FILES=()
while IFS= read -r f; do TEST_FILES+=("$f"); done < <(
  { ls "$KIT_DIR"/tests/*.sh 2>/dev/null || true
    find "$KIT_DIR/lib" -path '*/tests/*' ! -path '*/fixtures/*' \( -name '*.sh' -o -name '*.py' \) 2>/dev/null
  } | sort)

# One-pass reference index. The old generator ran one `grep -lE` per feature over every
# spec and every test (about 124 features x 7 MB, ~46 s of CPU). Now ONE awk reads each
# corpus file once and answers every feature at once.
#
# Matching semantics are the old grep's, unchanged: a file matches a token when some line
# matches `(^|[^A-Za-z0-9_-])TOKEN([^A-Za-z0-9_-]|$)`, TOKEN read as an ERE.
#   - A TOKEN made only of [A-Za-z0-9_-] can match only as a whole maximal run of those
#     characters (both neighbours are outside the class), so the awk splits each line on
#     the complement class and looks the runs up in a set. Exact, and no per-token scan.
#   - Any other TOKEN (a `.sh` basename, a verb name with a space) keeps its regex: a
#     line is tested with the same pattern, behind a cheap prefilter on the token's
#     leading literal run (a match must contain it).
# The awk also formats the Specs, Tests and Dispatched-by cells (cap_list, `sort -uV` of
# SPEC numbers, bytewise `sort -u` of names), so the shell spawns no pipeline per row.
# Query lines in: `<key> TAB <D|-> TAB <token> [TAB <token>...]`; lines out: `<key> TAB <specs>
# TAB <tests> TAB <dispatched-by>`. Only POSIX awk is assumed (macOS awk is the one-true-awk).
REF_AWK='
function cap(arr, n,   i, s) {
  if (n == 0) return "-"
  s = ""
  for (i = 1; i <= n && i <= 3; i++) s = s (i > 1 ? ", " : "") arr[i]
  if (n > 3) s = s " +" (n - 3)
  return s
}
function sort_str(arr, n,   i, j, v) {
  for (i = 2; i <= n; i++) {
    v = arr[i]
    for (j = i - 1; j >= 1 && arr[j] > v; j--) arr[j + 1] = arr[j]
    arr[j + 1] = v
  }
}
function sort_spec(arr, n,   i, j, v, nv) {
  for (i = 2; i <= n; i++) {
    v = arr[i]; nv = specnum[v]
    for (j = i - 1; j >= 1 && (specnum[arr[j]] > nv || (specnum[arr[j]] == nv && arr[j] > v)); j--) arr[j + 1] = arr[j]
    arr[j + 1] = v
  }
}
function base_of(p,   i) { i = match(p, /[^\/]*$/); return substr(p, i) }
function note_hit(t, f) {
  if (hit[t, f] != 1) { hit[t, f] = 1; tfc[t]++; tf[t, tfc[t]] = f }
}
BEGIN { cls = "[^A-Za-z0-9_-]" }
G == "Q" {
  nq++
  m = split($0, part, "\t")
  qkey[nq] = part[1]; qd[nq] = part[2]; qtc[nq] = m - 2
  for (k = 3; k <= m; k++) {
    tok = part[k]; qtok[nq, k - 2] = tok
    if (tok in tid) continue
    nt++; tid[tok] = nt
    if (tok ~ /^[A-Za-z0-9_-]+$/) pure[tok] = nt
    else {
      nnp++; npt[nnp] = nt
      nprx[nnp] = "(^|" cls ")" tok "(" cls "|$)"
      lead = tok; sub(/[^A-Za-z0-9_-].*$/, "", lead)
      if (lead == "") nopre = 1
      else npre = npre (npre == "" ? "" : "|") lead
    }
  }
  next
}
FNR == 1 { fid++; fgrp[fid] = G; fname[fid] = FILENAME }
{
  n = split($0, w, cls "+")
  for (i = 1; i <= n; i++) if (w[i] in pure) note_hit(pure[w[i]], fid)
  if (nnp > 0 && (nopre || $0 ~ npre))
    for (j = 1; j <= nnp; j++)
      if (hit[npt[j], fid] != 1 && $0 ~ nprx[j]) note_hit(npt[j], fid)
}
END {
  for (q = 1; q <= nq; q++) {
    nsp = 0; ntn = 0; ndn = 0
    for (k = 1; k <= qtc[q]; k++) {
      t = tid[qtok[q, k]]
      for (i = 1; i <= tfc[t]; i++) {
        f = tf[t, i]
        if (seen[f] == q) continue
        seen[f] = q
        g = fgrp[f]; p = fname[f]
        if (g == "S") {
          b = base_of(p)
          if (match(b, /^SPEC-[0-9]+-/)) { v = substr(b, 1, RLENGTH - 1); specnum[v] = substr(v, 6) + 0 }
          else { v = p; specnum[v] = 0 }
          if (sdup[q, v] != 1) { sdup[q, v] = 1; sp[++nsp] = v }
        } else if (g == "T") {
          v = base_of(p)
          if (tdup[q, v] != 1) { tdup[q, v] = 1; tn[++ntn] = v }
        } else if (qd[q] == "D") {
          if (g == "C") { v = base_of(p); sub(/\.md$/, "", v) }
          else { v = p; sub(/\/SKILL\.md$/, "", v); v = base_of(v) " (skill)" }
          if (ddup[q, v] != 1) { ddup[q, v] = 1; dn[++ndn] = v }
        }
      }
    }
    sort_spec(sp, nsp); sort_str(tn, ntn); sort_str(dn, ndn)
    printf "%s\t%s\t%s\t%s\n", qkey[q], cap(sp, nsp), cap(tn, ntn), cap(dn, ndn)
  }
}'

# Fills REF_KEYS / REF_SPEC / REF_TEST / REF_DISP (parallel arrays; bash 3.2 has no
# associative arrays) with one awk pass over every spec, test, command, and skill file.
REF_KEYS=(); REF_SPEC=(); REF_TEST=(); REF_DISP=()
build_queries() { # stdout: one query line per feature
  local f name rel desc base hook tab pat_tokens
  tab="$(printf '\t')"
  for f in "$KIT_DIR"/commands/*.md; do
    name="$(basename "$f" .md)"; printf 'c:%s\t-\t%s\n' "$name" "$name"
  done
  for f in "$KIT_DIR"/agents/*.md; do
    name="$(basename "$f" .md)"; printf 'a:%s\tD\t%s\n' "$name" "$name"
  done
  for f in "$KIT_DIR"/skills/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"; printf 's:%s\t-\t%s\n' "$name" "$name"
  done
  for f in "$KIT_DIR"/hooks/*.sh; do
    name="$(basename "$f" .sh)"; printf 'h:%s\t-\t%s\n' "$name" "$name"
  done
  while IFS="$tab" read -r rel name desc; do
    [ -n "$rel" ] || continue
    base="$(basename "$rel")"
    pat_tokens="$base$tab$name"
    # a verb also counts tests (and specs) naming a hook that calls its script
    while IFS= read -r hook; do
      [ -n "$hook" ] && pat_tokens="$pat_tokens$tab$hook"
    done < <(grep -lE "$(token_pat "$base")" "$KIT_DIR"/hooks/*.sh 2>/dev/null | sed -E 's|.*/||')
    printf 'v:%s:%s\t-\t%s\n' "$rel" "$name" "$pat_tokens"
  done < <(verb_markers)
}

load_refs() {
  local qfile="$1" rfile="$2" key spec tst disp f
  local specs=() cmds=() skills=()
  for f in "$KIT_DIR"/docs/specs/SPEC-*.md; do [ -f "$f" ] && specs+=("$f"); done
  for f in "$KIT_DIR"/commands/*.md; do [ -f "$f" ] && cmds+=("$f"); done
  for f in "$KIT_DIR"/skills/*/SKILL.md; do [ -f "$f" ] && skills+=("$f"); done
  build_queries > "$qfile"
  awk "$REF_AWK" G=Q "$qfile" \
    G=S ${specs[@]+"${specs[@]}"} \
    G=T ${TEST_FILES[@]+"${TEST_FILES[@]}"} \
    G=C ${cmds[@]+"${cmds[@]}"} \
    G=K ${skills[@]+"${skills[@]}"} > "$rfile"
  while IFS="$(printf '\t')" read -r key spec tst disp; do
    REF_KEYS+=("$key"); REF_SPEC+=("$spec"); REF_TEST+=("$tst"); REF_DISP+=("$disp")
  done < "$rfile"
}

ref_lookup() { # <key> -> sets R_SPEC R_TEST R_DISP
  local i=0 n="${#REF_KEYS[@]}"
  R_SPEC="-"; R_TEST="-"; R_DISP="-"
  while [ "$i" -lt "$n" ]; do
    if [ "${REF_KEYS[$i]}" = "$1" ]; then
      R_SPEC="${REF_SPEC[$i]}"; R_TEST="${REF_TEST[$i]}"; R_DISP="${REF_DISP[$i]}"
      return
    fi
    i=$((i + 1))
  done
}

hook_events() { # <basename.sh>
  local ev
  ev=$(jq -r --arg f "hooks/$1" '
        .hooks | to_entries[] | .key as $k | .value[] | .hooks[]
        | select(.command | endswith($f)) | $k' \
        "$KIT_DIR/hooks/hooks.json" 2>/dev/null | sort -u \
      | awk 'NR>1 {printf "+"} {printf "%s", $0} END {print ""}')
  if [ -z "$ev" ] && jq -r '.statusLine.command // ""' "$KIT_DIR/settings.json" 2>/dev/null \
      | grep -q "$1"; then
    ev="StatusLine"
  fi
  printf '%s' "${ev:--}"
}

hook_desc() { # <file>
  # header-comment convention: `# <name>.sh -- <description>`; fallback: the first
  # comment line with the `<name>.sh` prefix (and its separator) stripped
  local d
  d="$(awk -F' -- ' '/^# / && / -- / { print $2; exit }' "$1")"
  if [ -z "$d" ]; then
    d="$(awk '/^# / { sub(/^# /, ""); print; exit }' "$1" \
      | sed -E "s/^$(basename "$1")[[:space:]]*[,-]*[[:space:]]*//; s/^\xe2\x80\x94[[:space:]]*//")"
  fi
  printf '%s' "$d"
}

# verb_markers: "<file>\t<name>\t<description>" per declared verb, sorted by name.
verb_markers() {
  local f rel
  { grep -rlE '^# kit-verb: ' "$KIT_DIR/lib" --include='*.sh' --include='*.py' 2>/dev/null || true; } \
    | sort | while IFS= read -r f; do
      rel="${f#"$KIT_DIR"/}"
      awk -v rel="$rel" 'NR > 40 { exit }
        /^# kit-verb: / { line = substr($0, 13); i = index(line, " | ")
          if (i > 0) printf "%s\t%s\t%s\n", rel, substr(line, 1, i - 1), substr(line, i + 3) }' "$f"
    done | sort -t"$(printf '\t')" -k2,2
}

verbs_table() {
  echo "## Verbs"
  echo ""
  echo "| Verb | Trigger | Source | Description | Specs | Tests |"
  echo "|---|---|---|---|---|---|"
  local rel name desc
  while IFS="$(printf '\t')" read -r rel name desc; do
    [ -n "$rel" ] || continue
    ref_lookup "v:$rel:$name"
    printf '| `%s` | `[V]` | `%s` | %s | %s | %s |\n' \
      "$name" "$rel" "$(clip "$desc")" "$R_SPEC" "$R_TEST"
  done < <(verb_markers)
  echo ""
}

commands_table() {
  echo "## Commands"
  echo ""
  echo "| Command | Trigger | Description | Specs | Tests |"
  echo "|---|---|---|---|---|"
  local f name dmi trig
  for f in "$KIT_DIR"/commands/*.md; do
    name="$(basename "$f" .md)"
    dmi="$(fm_field "$f" disable-model-invocation)"
    trig='[H/I]'; [ "$dmi" = "true" ] && trig='[H]'
    ref_lookup "c:$name"
    printf '| `/kit:%s` | `%s` | %s | %s | %s |\n' \
      "$name" "$trig" "$(clip "$(fm_field "$f" description)")" \
      "$R_SPEC" "$R_TEST"
  done
  echo ""
}

agents_table() {
  echo "## Agents"
  echo ""
  echo "| Agent | Trigger | Dispatched by | Description | Specs | Tests |"
  echo "|---|---|---|---|---|---|"
  local f name
  for f in "$KIT_DIR"/agents/*.md; do
    name="$(basename "$f" .md)"
    ref_lookup "a:$name"
    printf '| `%s` | `[D]` | %s | %s | %s | %s |\n' \
      "$name" "$R_DISP" \
      "$(clip "$(fm_field "$f" description)")" \
      "$R_SPEC" "$R_TEST"
  done
  echo ""
}

skills_table() {
  echo "## Skills"
  echo ""
  echo "| Skill | Trigger | Description | Specs | Tests |"
  echo "|---|---|---|---|---|"
  local f name dmi trig
  for f in "$KIT_DIR"/skills/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    dmi="$(fm_field "$f" disable-model-invocation)"
    trig='[I]'; [ "$dmi" = "true" ] && trig='[H]'
    ref_lookup "s:$name"
    printf '| `%s` | `%s` | %s | %s | %s |\n' \
      "$name" "$trig" "$(clip "$(fm_field "$f" description)")" \
      "$R_SPEC" "$R_TEST"
  done
  echo ""
}

hooks_table() {
  echo "## Hooks"
  echo ""
  echo "| Hook | Trigger | Event | Description | Specs | Tests |"
  echo "|---|---|---|---|---|---|"
  local f base name
  for f in "$KIT_DIR"/hooks/*.sh; do
    base="$(basename "$f")"
    name="$(basename "$f" .sh)"
    ref_lookup "h:$name"
    printf '| `%s` | `[E]` | %s | %s | %s | %s |\n' \
      "$base" "$(hook_events "$base")" "$(clip "$(hook_desc "$f")")" \
      "$R_SPEC" "$R_TEST"
  done
  echo ""
}

generate() {
  local out="${1:-$KIT_DIR/docs/FEATURES.md}"
  local tmp="$out.tmp.$$" qfile rfile
  qfile="$(mktemp)"; rfile="$(mktemp)"
  # expand the paths NOW: the trap fires at script exit, after the locals are gone
  trap "rm -f '$tmp' '$qfile' '$rfile'" EXIT
  load_refs "$qfile" "$rfile"
  {
    echo "---"
    echo "title: Feature registry"
    echo "status: GENERATED projection"
    echo "generator: lib/registry/feature-registry.sh"
    echo "---"
    echo ""
    echo "# Feature registry"
    echo ""
    echo "GENERATED , do not hand-edit. Regenerate: \`bash lib/registry/feature-registry.sh generate\`. One row per live feature; freshness pinned by \`tests/test-meta.sh\` and refused pre-push by \`hooks/ship-gate.sh\`, both through \`feature-registry.sh check\`. Trigger classes per \`docs/workflow-paths.md\` section 1: \`[H]\` human-typed, \`[H/I]\` human-or-intent, \`[I]\` intent-read, \`[E]\` event-fired, \`[D]\` dispatched, \`[V]\` lib verb declared by a \`# kit-verb:\` header line. Refs are exact-token greps: Specs over \`docs/specs/\`, Tests over \`tests/*.sh\` + \`lib/*/tests/**\` (a verb also counts tests naming a hook that calls its script), Dispatched-by over \`commands/*.md\` + \`skills/*/SKILL.md\` (skill dispatchers marked \`(skill)\`); \`-\` means no reference found (a coverage gap, not always a defect: read-only agents may be deliberately untested)."
    echo ""
    commands_table
    agents_table
    skills_table
    hooks_table
    verbs_table
  } > "$tmp"
  mv -f "$tmp" "$out"
}

# check [file] -- is the committed projection current? Exit 0 fresh, 1 drifted.
# FEATURE_REGISTRY_KEEP=<path> also copies the freshly generated bytes there, so a caller
# that needs both the verdict and a second copy (tests/test-meta-docs-registry.sh pins
# determinism that way) pays for one generator run, not two.
#
# tests/test-meta.sh pins freshness by regenerating to a temp file and diffing, and
# every caller who wanted that answer outside the suite rebuilt the same three lines
# by hand. Doing it by hand also loses the drift itself: the suite reports a red
# assertion, not WHICH rows moved, so the reader regenerates blind. This prints the
# diff. `--fix` regenerates in place, which is the whole remedy every time.
#
# Worth knowing before reading a surprising diff: the Tests column is an exact-token
# grep over tests/*.sh, so PROSE counts. A comment in a test file that names a
# feature wires that file to the feature and moves this projection, which is how a
# comment explaining an unrelated flake drifted three rows on 2026-09-14.
check() {
  local out="${1:-docs/FEATURES.md}" fix="" tmp rc=0
  [ "$out" = "--fix" ] && { fix=1; out="${2:-docs/FEATURES.md}"; }
  if [ ! -f "$out" ]; then
    echo "feature-registry: $out does not exist; run 'generate' first" >&2
    return 1
  fi
  tmp="$(mktemp)"
  generate "$tmp"
  [ -z "${FEATURE_REGISTRY_KEEP:-}" ] || cp -f "$tmp" "$FEATURE_REGISTRY_KEEP"
  if diff -q "$tmp" "$out" >/dev/null 2>&1; then
    echo "feature-registry: $out is fresh"
  else
    rc=1
    if [ -n "$fix" ]; then
      mv -f "$tmp" "$out"
      echo "feature-registry: $out regenerated"
      return 0
    fi
    echo "feature-registry: $out has DRIFTED; regenerate with 'feature-registry.sh check --fix'" >&2
    diff "$tmp" "$out" >&2 || true
  fi
  rm -f "$tmp"
  return "$rc"
}

case "${1:-}" in
  generate) shift; generate "$@" ;;
  check)    shift; check "$@" ;;
  *) echo "usage: feature-registry.sh generate [outfile]" >&2
     echo "       feature-registry.sh check [--fix] [outfile]" >&2; exit 64 ;;
esac
