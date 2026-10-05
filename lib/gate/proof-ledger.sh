#!/usr/bin/env bash
# proof-ledger.sh -- the proof-of-done ship/merge gate (diff-keyed, spec-independent).
#
# Turns the proof-of-done convention (docs/verification/README.md) from advice into a
# wall: a load-bearing change cannot ship/merge without a matching proof-of-done entry.
# Unlike the lane gate (gate-ledger.sh), this keys off the BRANCH DIFF, not a spec, so it
# fires the same whether the work came through /kit:execute or a freeform /goal loop.
#
# A change's PROOF CLASS comes from its diff (consistent with lib/gate/proof-gate.sh):
#   stateful   -- deploy / migration / data / persistent-state paths or commit subjects
#                 (subjects count only when the diff touches a non-doc, non-test path).
#                 Pass = a fresh verification entry with a recorded run AND a rollback
#                 note (or [UNAVAILABLE: reason]).
#   behavioral -- changes behavior (code/lib/commands/agents/hooks/tests).
#                 Pass = a fresh verification entry with a green run AND a NEGATIVE CONTROL
#                 ([gate] negative_control = full drops the control unless a hard path or a
#                 full-lane spec is involved; default `always`).
#   inert      -- docs / comments / cosmetic (markdown-only diff). Pass (no ritual).
#
# "Fresh" = the branch diff itself added/modified the docs/verification/*.md entry, so an
# old proof from unrelated work does not satisfy a new change.
#
# An explicit, LOGGED override always exists (never a silent bypass).
#
# FAILS OPEN on genuine ambiguity (no repo, empty diff, no base, missing tooling): a gate
# bug must never block unrelated work. Exit 1 from `check` = block.
#
# Subcommands:
#   classify <root> <base>            print inert|behavioral|stateful for the branch diff
#   check    <root> <base> [slug]     exit 0 if the proof requirement is met (or overridden
#                                     or inert); else exit 1 + what is missing
#   override <slug> <reason>          log a human override for this branch (leaves a trace)
#   is-overridden <slug>              exit 0 if an override is logged
#   proof-files <root> <base>         the proof files the branch added or changed, one per line
#   captured-output <proof-file>      the real lines under the file's Output: slots
#   images <proof-file> <root>        "link<TAB>repo path" per embedded image that exists
#   negctl   <root> <test-cmd> <mutate-cmd>
#   negctl   --base-ref <ref> <root> <test-cmd>
#   negctl   --at <sha> [--path <subdir>] [--setup <cmd>] <root> <test-cmd> <mutate-cmd>
#   negctl   --parallel <N> [--slot-env VAR=start:step]... <root> <test-cmd> <mutate-cmd>...
#                                     forwards to lib/gate/negctl.sh (the mechanised negative
#                                     control; FAILS CLOSED, prints the block check() reads.
#                                     --base-ref mode proves the control against a git ref
#                                     instead of mutating the tree, so it works on a dirty
#                                     shared checkout; --parallel runs several controls N at
#                                     a time, each in its own throwaway worktree copy)
set -uo pipefail

PROOF_LEDGER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$PROOF_LEDGER_DIR/.." && pwd)"  # the lib/ dir; cross-subsystem siblings resolve as "$LIB_ROOT/<subsystem>/<file>"
# Durable run-telemetry root: resolve + one-time additive migration.
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
# The ONE append substrate: the override write routes through ledger_append.
# shellcheck source=lib/ledger/ledger.sh
source "$LIB_ROOT/ledger/ledger.sh" || { echo "FATAL: lib/ledger/ledger.sh missing or unreadable" >&2; exit 1; }
# The config-layer resolver ([ledger] wiring): the delivery-ratio thresholds below
# read through it. kit-log-dir.sh already sources it, but source directly too so this file's
# dependency on kit-config.sh is explicit, not incidental to another lib's internals.
# shellcheck source=lib/config/kit-config.sh
source "$LIB_ROOT/config/kit-config.sh" || { echo "FATAL: lib/config/kit-config.sh missing or unreadable" >&2; exit 1; }
# shellcheck source=lib/spec/spec-find.sh
# A stale install without spec-find.sh keeps the root-only lookup (mirrors hooks/ship-gate.sh).
if ! source "$LIB_ROOT/spec/spec-find.sh" 2>/dev/null; then
  spec_files() { ls "$1"/docs/specs/SPEC-*.md 2>/dev/null; return 0; }
  spec_for_slug() { [ -n "$2" ] || return 0; ls "$1"/docs/specs/SPEC-*-"$2".md 2>/dev/null | head -1 || true; return 0; }
fi
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)" || exit 1
OVERRIDE_LOG="$LOG_DIR/proof-overrides.log"
OVERRIDE_STREAM="proof-overrides.log"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
slugify() { printf '%s' "$1" | tr '/ ' '--' | tr -cd '[:alnum:]._-'; }

# changed files on the branch (base..HEAD), plus working-tree changes so a not-yet-
# committed proof still counts during an interactive build. --no-renames lists both sides of
# a rename: a `git mv db/migrations/x.sql tests/` must still show the migrations path.
_changed() {
  local root="$1" base="$2"
  { git -C "$root" diff --name-only --no-renames "$base"..HEAD 2>/dev/null
    git -C "$root" diff --name-only --no-renames HEAD 2>/dev/null
    git -C "$root" diff --name-only --no-renames --cached 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | sed '/^$/d'
}

_subjects() { git -C "$1" log "$2"..HEAD --format='%s' 2>/dev/null || true; }

classify() {
  local root="${1:-}" base="${2:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: classify <root> <base>" >&2; return 64; }
  local changed subjects blob
  changed="$(_changed "$root" "$base")"
  [ -n "$changed" ] || { echo inert; return 0; }   # empty diff: nothing to gate

  # inert FIRST: a markdown/txt-only diff is docs, never load-bearing, regardless of what the
  # commit subject says. Checking stateful keywords against the subject before this misread a
  # markdown-only "migrate" doc change as stateful (see , the classify-md-inert dogfood).
  # The project's own .kit.toml is harness config (which gates run, which modules are wired,
  # where the ledger lives), never project behavior: a .kit.toml-only diff owes no proof-of-done,
  # whatever key it touches; otherwise flipping a [gate] key would itself be gated. A diff that
  # also touches code is classified by the code.
  if [ -z "$(printf '%s\n' "$changed" | grep -vE '\.(md|txt|markdown)$|(^|/)\.kit\.toml$')" ]; then
    echo inert; return 0
  fi

  # Subject words count only when a non-doc path is also a non-test path. A tests-only diff
  # is classified by its paths alone: its subject describes the test, and a negative-control
  # commit says "restore". Any path outside the test pattern keeps the subject signal.
  # Capture, never `grep -q`: under pipefail its early exit SIGPIPEs the upstream grep on a
  # large diff and the guard reads "no source path", which fails open.
  # A test path is a root tests/ or test/ tree, a __tests__/ dir anywhere, or a code file named
  # test_*, *_test.* or *.test.*. Data and config files (.sql, .yaml, .json) never count as
  # tests, and a nested test/ dir (k8s/overlays/test/) is not a test tree.
  local code_ext='(py|go|rs|rb|js|jsx|ts|tsx|sh|bash|swift|kt|java|ex|exs)'
  subjects=""
  if [ -n "$(printf '%s\n' "$changed" | grep -vE '\.(md|txt|markdown)$|(^|/)\.kit\.toml$' \
       | grep -vE "^(tests?|__tests__)/|(^|/)__tests__/|(^|/)test_[^/]*\.${code_ext}\$|[._]test\.${code_ext}\$")" ]; then
    subjects="$(_subjects "$root" "$base")"
  fi
  blob="$(printf '%s\n%s' "$changed" "$subjects" | tr 'A-Z' 'a-z')"
  # stateful: deploy / migration / data / persistent-state signals (only reached when the diff
  # touches non-doc files, so a docs-only commit can no longer be misclassified by its subject).
  if grep -qE 'deploy|rollout|production|migrat|schema|data[ -]model|database|/db/|\bseed\b|backup|restore|persistent|drop .*(table|column)|alter table|data loss' < <(printf '%s' "$blob"); then
    echo stateful; return 0
  fi
  echo behavioral
}

# deployable <root> <base>: prints yes|no by mapping classify()'s existing "stateful" class
# to "deployable" (: deployable-done). PURELY ADDITIVE -- a relabel
# of classify()'s output for readability at call sites, never a second classifier. Does not
# read or touch classify()'s logic, and classify()/check() are otherwise byte-unchanged.
deployable() {
  local root="${1:-}" base="${2:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: deployable <root> <base>" >&2; return 64; }
  [ "$(classify "$root" "$base")" = "stateful" ] && echo yes || echo no
}

# delivery-ratio <root> <base>: ADVISORY. Splits this branch's ADDED lines into
# "real deliverable" (code + user-facing docs) vs "proof/ceremony" (proof-of-done,
# verification, specs, impl-notes, ADRs, tests) and flags the hollow signature: a lot
# of proof wrapped around a near-zero real change. NEVER blocks -- it is a heuristic
# with real false positives (a legit docs/research sub-goal is proof-heavy by design;
# a 1-line regex fix can be load-bearing), so it only PRINTS a NOTICE/THIN-WARN/OK line
# for a reviewer or `mega status` to surface. Rationale: the proof-of-done gate checks
# that proof EXISTS, not that delivery is PROPORTIONATE, so a thin docs/reconcile
# sub-goal can pass by padding proof (2026-07-05 delivery audit; ADR "delivery ratio").
# Precedence ([ledger] wiring): env var > project .kit.toml > kit-root kit.toml >
# hardcoded default, via kit_config_get. An explicit env var still wins over config, same
# back-compat contract as kit_resolve_log_dir.
KIT_DELIVERY_RATIO_WARN="${KIT_DELIVERY_RATIO_WARN:-$(kit_config_get ledger.delivery_ratio_warn 3)}"    # proof >= N*real ...
KIT_DELIVERY_REAL_FLOOR="${KIT_DELIVERY_REAL_FLOOR:-$(kit_config_get ledger.delivery_real_floor 40)}"   # ... AND real < FLOOR => THIN-WARN
delivery_ratio() {
  local root="${1:-}" base="${2:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: delivery-ratio <root> <base>" >&2; return 64; }
  git -C "$root" rev-parse --verify -q "$base" >/dev/null 2>&1 \
    || { echo "real=0 proof=0 | SKIP: base '$base' is not a commit"; return 0; }
  local real=0 proof=0 add del path
  while IFS=$'\t' read -r add del path; do
    [ -n "$path" ] || continue
    [ "$add" = "-" ] && continue                            # binary file: no line count
    case "$path" in
      */proof-of-done.md|docs/proof/*|*/docs/proof/*|docs/verification/*|*/docs/verification/*|docs/specs/*|*/docs/specs/*|docs/implementation-notes/*|*/docs/implementation-notes/*|docs/runs/*|*/docs/runs/*|docs/decisions/*|*/docs/decisions/*|tests/*|*/tests/*)
        proof=$((proof+add)) ;;
      *.lock|*/uv.lock|*/package-lock.json|*/pnpm-lock.yaml|*/Cargo.lock|*/go.sum)
        : ;;                                                # generated lockfiles: ignore
      *)
        real=$((real+add)) ;;
    esac
  done < <(git -C "$root" diff --numstat "$base"..HEAD 2>/dev/null)

  local verdict
  if [ "$real" -eq 0 ]; then
    if [ "$proof" -gt 0 ]; then
      verdict="NOTICE: docs/proof-only branch -- expected for a docs/research sub-goal, SUSPECT for a build/rewrite/enforce claim"
    else
      verdict="OK: no added lines"
    fi
  elif [ "$proof" -ge $((KIT_DELIVERY_RATIO_WARN*real)) ] && [ "$real" -lt "$KIT_DELIVERY_REAL_FLOOR" ]; then
    verdict="THIN-WARN: proof >= ${KIT_DELIVERY_RATIO_WARN}x real and real < ${KIT_DELIVERY_REAL_FLOOR} -- confirm delivery matches the sub-goal's claim (advisory heuristic; false positives exist)"
  else
    verdict="OK"
  fi
  echo "real=$real proof=$proof | $verdict"
}

# the verification-log files this branch added/modified (excludes the convention README).
# Two accepted shapes, both location-agnostic: any `docs/verification/<slug>.md` (at the
# repo root or nested under whatever owns it) and any path ending `/proof-of-done.md`. The
# content check in check() validates both the same way; location is just where the proof
# lives.
#
# The nested case used to be spelled out as `tools/<name>/docs/verification/`, which only
# covered a monorepo TOOL. ops-toolkit's co-location rule also puts an experiment's proof at
# `experiments/<slug>/docs/verification/<feature>.md`, and that matched nothing, so a real
# proof was invisible and the gate fell through to the override branch and refused the source
# change (hit 2026-08-25). Enumerating owner directories is the bug: every new co-location
# home needs another alternative, and the failure is silent. Matching `docs/verification/` at
# any depth is both smaller and closed over future owners, and it grants nothing the
# already-anywhere `/proof-of-done.md` rule did not.
_fresh_proof_files() {
  local root="$1" base="$2"
  { git -C "$root" diff --name-only --no-renames "$base"..HEAD 2>/dev/null
    git -C "$root" diff --name-only --no-renames HEAD 2>/dev/null
    git -C "$root" diff --name-only --no-renames --cached 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | grep -E '(^|/)docs/verification/.+\.md$|(^|/)proof-of-done\.md$' | grep -v '/README\.md$' || true
}

# Repo identity for override scoping. The override log is machine-local and now
# keys each entry by repo+slug, so a `backlog-reconcile` override logged in one repo cannot
# short-circuit the ship-gate for the SAME slug in an unrelated repo (the family-office ->
# console-labs collision that hid a real proof). Repo id = the git COMMON dir's parent (the
# shared repo root), absolute, so ALL worktrees of one repo share a key -- keying on
# --show-toplevel would give every `.claude/worktrees/<name>` checkout a different id under
# the kit's own always-worktree policy, silently blocking a push from a sibling worktree.
# The raw absolute path is the key (not a lossy slug: `tr '/ ' '--'` collapsed `foo/bar`
# and `foo-bar` onto the same id, review-flagged); only `|` is stripped for delimiter safety.
# A non-git dir falls back to the ABSOLUTE cwd so two relative "." calls in different dirs
# never collide onto the same key.
_repo_id() {
  local d="${1:-.}" common
  common="$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)" || {
    printf '%s' "$( (cd "$d" 2>/dev/null && pwd -P) || printf '%s' "$d")" | tr -d '|'; return
  }
  case "$common" in
    /*) : ;;
    *) common="$( (cd "$d" 2>/dev/null && cd "$(dirname "$common")" 2>/dev/null && pwd -P) )/$(basename "$common")" ;;
  esac
  common="${common%/.git}"          # the shared repo root, identical across all worktrees
  printf '%s' "$common" | tr -d '|'
}

# negctl forwards to lib/gate/negctl.sh: a tree-mutating, FAIL-CLOSED tool does not belong
# inside the gate (which FAILS OPEN on ambiguity by contract); the verb stays for callers.
negctl() { bash "$PROOF_LEDGER_DIR/negctl.sh" "$@"; }

is_overridden() {
  local slug repo
  slug="$(slugify "${1:-}")"; repo="$(_repo_id "${2:-.}")"
  [ -n "$slug" ] || return 1
  [ -f "$OVERRIDE_LOG" ] || return 1
  # FIELD-anchored match (+ review security lens): compare the repo/slug FIELDS by
  # position, never a substring of the whole line. A free substring (`grep -F "| $repo | $slug |"`)
  # let a crafted `reason` embedding "| <victim-repo> | <victim-slug> |" forge a match for a
  # repo/slug the operator never touched -- the very cross-repo bypass this change closes.
  # FS is a single "|" (portable across awk variants; a multi-char " | " FS is a regex BSD awk
  # mishandled); fields are trimmed. repo has "|" stripped and slug is charset-restricted, so
  # the reason (field 5+) can never shift or forge fields 2/3/4. Legacy entries carry no repo
  # field ($4 != OVERRIDE) so they match no repo -> fail CLOSED.
  awk -F'|' -v r="$repo" -v s="$slug" '
    function trim(x){ gsub(/^[ \t]+|[ \t]+$/,"",x); return x }
    trim($2)==r && trim($3)==s && trim($4)=="OVERRIDE" { found=1; exit }
    END { exit(found?0:1) }' "$OVERRIDE_LOG"
}

override() {
  local slug raw reason repo
  raw="${1:-}"; shift 2>/dev/null || { echo "usage: override <slug> <reason>" >&2; return 64; }
  reason="${*:-}"; slug="$(slugify "$raw")"
  [ -n "$slug" ] && [ -n "$reason" ] || { echo "usage: override <slug> <reason>" >&2; return 64; }
  # CONTRACT: the override is scoped to the repo it is logged FROM, so run it from
  # inside that repo's tree. Refuse when cwd is not a git repo, rather than log a cwd-keyed
  # entry that will never match a push (review: the write side must not silently no-op). This
  # is the write twin of check()'s explicit-$root read; it also closes the cwd-ambiguity class
  # noted in _meta/megagoals/_archive/kit-north-star/FEEDBACK.md.
  if ! git -C . rev-parse --git-common-dir >/dev/null 2>&1; then
    echo "override: cwd is not a git repo. Run this from inside the repo you are overriding for; nothing logged." >&2
    return 66
  fi
  repo="$(_repo_id ".")"
  ledger_append "$OVERRIDE_STREAM" "$(printf '%s | %s | %s | OVERRIDE | %s' "$(now)" "$repo" "$slug" "$reason")" || return 1
  echo "proof-of-done override logged for slug '$slug' in repo '$repo' (trace: $OVERRIDE_LOG)"
}

# _committed_images <proof-file> <root>: one "link<TAB>repo-relative path" line per embedded
# image whose target actually EXISTS in the tree (resolved relative to the proof file's dir,
# then the repo root). Closes the fabrication hole: a bare `![x](missing.gif)` string must not
# count as "it ran", the picture has to really be there. A committed proof image satisfies this
# at push time; a dangling or typo'd reference prints nothing.
_committed_images() {
  local pf="$1" root="$2" link path rel
  [ -f "$pf" ] || return 0
  rel="$(dirname "${pf#"$root"/}")"
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    path="${link%%[#?]*}"          # strip #anchor / ?query
    path="${path#./}"
    if [ -f "$(dirname "$pf")/$path" ]; then
      [ "$rel" = . ] || path="$rel/$path"
      printf '%s\t%s\n' "$link" "$path"
    elif [ -f "$root/$path" ]; then
      printf '%s\t%s\n' "$link" "$path"
    fi
  done < <(grep -oiE '!\[[^]]*\]\([^)]*\.(png|gif|jpe?g|svg|webp)\)' "$pf" 2>/dev/null \
            | sed -E 's/^.*\(([^)]*)\)$/\1/')
}
_has_committed_image() { [ -n "$(_committed_images "$1" "$2")" ]; }

# _captured_output: stdin is proof text; prints the REAL lines held by its `Output` slots.
# A slot is a line `Output:` or `Output (<anything>):` (any case; a list bullet or bold is
# fine), or a heading `### Output`. Its lines are the text after the colon, then the lines
# below it, up to the first of:
#   - a run-table field at the start of a line or bullet (Command:/Exit:/Verdict:/Result:);
#     an INDENTED line never ends a slot, so a test that prints `Results: 12` stays output
#   - the next heading
#   - the end of the fenced block the slot opened (the fence must come before any content)
#     or sits in; a later, unrelated fence ends the slot instead of joining it
#   - a blank line once the slot has content (a heading slot runs to the next heading)
#   - an unindented paragraph after a blank line when the slot is still empty
# A fenced run block needs no label: inside a fence, the lines after an `Exit:` line, up to
# the fence's end, are output (field lines there are skipped, never counted). So a block of
# Command:/Exit:/Verdict: lines alone still holds nothing.
# Blank lines, fence lines, a bare `<placeholder>` and filler (`none`, `n/a`, `...`,
# `see ...`, `(see above)`) are not output, so a slot left empty prints nothing. This is
# what makes a green run CAPTURED: `Exit: 0` is a claim, the lines under `Output:` are what
# the run printed. It cannot judge whether pasted lines are true; that stays with review.
_captured_output() {
  awk '
    function real(s,   t) {
      gsub(/^[ \t>*]+|[ \t*]+$/, "", s); t = tolower(s)
      if (s ~ /^<[^>]*>$/ || t ~ /^(none|n\/a|na|tbd|todo|-+|\.\.\.+)$/ \
          || t ~ /^\((see|none|n\/a|tbd|omitted)[^)]*\)$/ || t ~ /^see[ \t]/) return ""
      return s
    }
    function emit(s,   r) { r = real(s); if (r != "") { print r; got = 1 } }
    # isout: an Output slot label (sets RSTART/RLENGTH); isfield: a run-table field line.
    function isout(x) { return match(x, /^[ \t>]*([-*+][ \t]+)?[*_]*output[ \t]*(\([^)]*\))?[*_]*:/) }
    function isfield(x) { return x ~ /^>?([-*+][ \t]+)?[*_]*(command|exit|verdict|result)[*_]*:/ }
    function open_slot(h) { slot = 1; own = 0; got = 0; gap = 0; hd = h; imp = 0 }
    { l = tolower($0) }
    /^[ \t>]*(```|~~~)/ {
      if (slot && !fence && !got && !hd) own = 1
      else if (slot && !hd) slot = 0
      fence = !fence; next
    }
    slot && own && imp && isout(l) { emit(substr($0, RSTART + RLENGTH)); next }
    slot && own && imp && isfield(l) { next }
    slot && own { emit($0); next }
    isout(l) { open_slot(0); emit(substr($0, RSTART + RLENGTH)); next }
    fence && l ~ /^[ \t>]*([-*+][ \t]+)?[*_]*exit[*_]*:/ { open_slot(0); own = 1; imp = 1; next }
    !fence && l ~ /^#+[ \t]+output([ \t(:].*)?$/ { open_slot(1); next }
    !slot { next }
    !fence && /^#/ { slot = 0; next }
    isfield(l) { slot = 0; next }
    /^[ \t]*$/ { if (got && !hd) slot = 0; else gap = 1; next }
    gap && !got && !hd && !fence && $0 !~ /^(  |\t)/ { slot = 0; next }
    { emit($0) }
  ' 2>/dev/null
}
_has_captured_output() { [ -n "$(_captured_output)" ]; }

# _negctl_required <root> <base> <slug>: prints yes|no, whether a behavioral proof must carry a
# NEGATIVE CONTROL. [gate] negative_control = always (default, every behavioral change) | full
# (only a hard-path diff per lane-classify, or a spec whose Lane: is full). A project-level
# `full` weakens the gate, so like gate-policy.sh it counts only when .kit.toml is tracked and
# clean; the operator and kit-root layers apply as-is. Anything unreadable or unknown means yes.
_negctl_required() {
  local root="$1" base="$2" slug="$3" mode pv spec lane changed
  mode="$(KIT_PROJECT_ROOT=/nonexistent kit_config_get gate.negative_control always 2>/dev/null)" || mode=always
  pv="$(_kit_toml_get "$root/.kit.toml" gate negative_control)"
  case "$pv" in
    always) mode=always ;;
    full) kit_config_tracked_clean "$root/.kit.toml" && mode=full ;;
  esac
  [ "$mode" = full ] || { echo yes; return 0; }
  [ -z "$slug" ] || spec="$(spec_for_slug "$root" "$slug")"
  if [ -n "${spec:-}" ]; then
    lane="$(grep -m1 -iE '^(\*\*)?Lane(\*\*)?:' "$spec" 2>/dev/null | sed -E 's/^(\*\*)?[Ll]ane(\*\*)?:(\*\*)?[[:space:]]*//; s/[[:space:]].*$//')"
    [ "$lane" = full ] && { echo yes; return 0; }
  fi
  local LC="$LIB_ROOT/classify/lane-classify.sh"
  [ -f "$LC" ] || { echo yes; return 0; }
  [ -z "$(KIT_PROJECT_ROOT="$root" bash "$LC" floor "$root" "$base" 2>/dev/null)" ] || { echo yes; return 0; }
  changed="$(_changed "$root" "$base" | tr '\n' ' ')"
  grep -qx 'flags: hard-path' < <(KIT_PROJECT_ROOT="$root" bash "$LC" explain --files "$changed" "negative control check" 2>/dev/null) \
    && { echo yes; return 0; }
  echo no
}

# --- the opt-in image rule (a [proof] visual = true diff owes one qualifying image) ------
# Everything below is dead code while proof.visual resolves false. When on, a behavioral
# diff touching a UI extension needs ONE of, checked after every existing rule passes:
#   R3a uploaded -- a changed docs/verification/<dir>/assets.json entry whose url sits
#     under <base>/<owner>/<repo>/ (base from the owner routing, ROOT-ONLY so a project
#     file can never redirect it), whose exact ![..](url) embed appears in a proof file the
#     branch changed, and whose fetched bytes hash to the entry's sha256.
#   R3b committed -- an image link in a changed proof file whose target git ls-files lists.
#   R3c local    -- a `status: local` entry whose cached file exists under
#     .kit/proof-assets/<slug>/, allowed only when a TRACKED, CLEAN project .kit.toml sets
#     assets = "local" (an uncommitted edit or an operator-level value is not opt-in).
# The gate never holds a fetched body: it pipes the fetch straight into the hasher.
# PROOF_ASSET_FETCH is the test seam (no check may touch the network but the default one).
# -q comes first: an operator's ~/.curlrc (proxy, output, header tricks) must never
# change what the gate fetches.
PROOF_ASSET_FETCH="${PROOF_ASSET_FETCH:-curl -q -fsS --proto =https --max-time 15 --max-filesize 3000000}"

# The trust rules for fields a committed manifest rides into the gate (the same shapes
# bin/proof-asset enforces at write time): a manifest ships in the PR, so its slug and
# file are validated before either is joined into a filesystem path.
_visual_slug_ok() { printf '%s' "$1" | grep -qE '^[a-z0-9][a-z0-9._-]*$'; }
_visual_file_ok() { printf '%s' "$1" | grep -qE '^[a-z0-9][a-z0-9._-]*\.(webp|png|gif|jpg)$'; }

# _visual_owner_repo <root>: "owner/repo" lowercased from the origin remote, empty when the
# remote is absent. `git@github.com:o/r.git` and `https://github.com/o/r` resolve the same.
_visual_owner_repo() {
  local u; u="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 0
  u="${u%/}"; u="${u%.git}"
  printf '%s' "$u" | tr ':' '/' | tr 'A-Z' 'a-z' | awk -F/ 'NF>1{print $(NF-1)"/"$NF}'
}

# _md_image_targets <file>: the raw (...) target of every ![..](...) link, one per line.
_md_image_targets() {
  [ -f "$1" ] || return 0
  grep -oiE '!\[[^]]*\]\([^)]*\.(png|gif|jpe?g|svg|webp)\)' "$1" 2>/dev/null \
    | sed -E 's/^.*\(([^)]*)\)$/\1/'
}

# _proofs_link_url <root> <proof-list> <url>: exit 0 when the exact ![..](url) embed appears
# in one of the branch's changed proof files.
_proofs_link_url() {
  local root="$1" plist="$2" url="$3" pf t
  while IFS= read -r pf; do
    [ -n "$pf" ] || continue
    while IFS= read -r t; do
      [ "$t" = "$url" ] && return 0
    done < <(_md_image_targets "$root/$pf")
  done <<< "$plist"
  return 1
}

# _visual_proof <root> <base>: exit 0 when one qualifying image exists; else print the R4
# block message (naming the case) on stderr and exit 1.
_visual_proof() {
  local root="$1" base="$2"
  local proofs manifests changed
  proofs="$(_fresh_proof_files "$root" "$base")"
  changed="$(_changed "$root" "$base")"
  manifests="$(printf '%s\n' "$changed" | grep -E '(^|/)docs/verification/[^/]+/assets\.json$' || true)"

  # R3b first (cheapest): a tracked image linked from a changed proof file, AND one the
  # branch itself changed. _committed_images resolves the link to a repo-relative
  # existing path; git ls-files decides tracked (a gitignored or untracked file, the
  # .kit/proof-assets/ cache, never counts), and membership in the branch's changed
  # files stops an old tracked public/logo.png from excusing a new UI diff forever.
  local pf ilink ipath
  while IFS= read -r pf; do
    [ -n "$pf" ] || continue
    while IFS=$'\t' read -r ilink ipath; do
      [ -n "$ipath" ] || continue
      git -C "$root" ls-files --error-unmatch "$ipath" >/dev/null 2>&1 \
        && grep -qxF "$ipath" < <(printf '%s\n' "$changed") && return 0
    done < <(_committed_images "$root/$pf" "$root")
  done <<< "$proofs"

  local owner_repo="" baseurl="" bkey
  owner_repo="$(_visual_owner_repo "$root")"
  if [ -n "$owner_repo" ]; then
    # the routing key is parameterized (proof.base_url_<owner>), so it goes through a
    # variable: the config-registry lint enumerates literal kit_config_get_root call sites.
    bkey="proof.base_url_${owner_repo%%/*}"
    baseurl="$(kit_config_get_root "$bkey" 2>/dev/null)"
  fi
  baseurl="${baseurl%/}"

  local assets_local=no
  if kit_config_tracked_clean "$root/.kit.toml" \
     && [ "$(_kit_toml_get "$root/.kit.toml" proof assets)" = "local" ]; then
    assets_local=yes
  fi

  local reasons="" pending=0 fetches=0 m mfile mslug n st url sha f by got
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    mfile="$root/$m"; [ -f "$mfile" ] || continue
    if ! command -v jq >/dev/null 2>&1 || ! jq -e . "$mfile" >/dev/null 2>&1; then
      reasons="${reasons}manifest unreadable (jq missing or invalid json): $m"$'\n'; continue
    fi
    mslug="$(jq -r '.slug // empty' "$mfile" 2>/dev/null)"
    [ -n "$mslug" ] || mslug="$(basename "$(dirname "$m")")"
    # Upload progress is the gitignored queue file, never the manifest: a leftover
    # .pending line (or a legacy pending status) is what the flush hint points at.
    n="$(jq '[.assets[]? | select(.status == "pending")] | length' "$mfile" 2>/dev/null)"
    [ "${n:-0}" -gt 0 ] 2>/dev/null && pending=1
    _visual_slug_ok "$mslug" && [ -s "$root/.kit/proof-assets/$mslug/.pending" ] && pending=1
    # fields joined on \x1f, never \t: read collapses consecutive IFS whitespace, so an
    # empty url/sha256 would shift the file field into url's slot.
    while IFS=$'\x1f' read -r st url sha f by; do
      [ -n "$st$url$sha$f$by" ] || continue
      # R3c local: the manifest entry's status is a local hint; only a tracked, clean
      # project opt-in plus a real cached file counts. slug and file are validated
      # before they join a path, so a crafted manifest can never read outside the cache.
      if [ "$assets_local" = yes ] && [ "$st" = "local" ] && [ -n "$f" ]; then
        if _visual_slug_ok "$mslug" && _visual_file_ok "$f" \
           && [ -f "$root/.kit/proof-assets/$mslug/$f" ]; then
          return 0
        fi
        reasons="${reasons}unsafe local entry (slug/file): $mslug/$f"$'\n'; continue
      fi
      # R3a uploaded: prefix, then url hygiene, the declared size, and the embed; only
      # then fetch + hash. A missing base url or owner/repo makes EVERY entry outside
      # the bucket.
      if [ -z "$baseurl" ] || [ -z "$owner_repo" ] || [ "${url#"$baseurl/$owner_repo/"}" = "$url" ]; then
        reasons="${reasons}url outside the proof bucket: ${url:-<unset>}"$'\n'; continue
      fi
      # curl normalizes '..' and decodes '%': either in the key could walk to another
      # repo's object under the same prefix and still hash-match.
      case "$url" in
        *..*|*%*) reasons="${reasons}unsafe url: $url"$'\n'; continue ;;
      esac
      # The declared size is checked before a byte is fetched (the fetch itself is
      # also capped by --max-filesize as the second line).
      if [ "${by:-0}" -gt 3000000 ] 2>/dev/null; then
        reasons="${reasons}declared size over the 3000000-byte cap: $url"$'\n'; continue
      fi
      if ! _proofs_link_url "$root" "$proofs" "$url"; then
        reasons="${reasons}image link not in a changed proof file: $url"$'\n'; continue
      fi
      # A check verifies at most 5 entries against the network: a long manifest can
      # never turn the gate into a fetch loop.
      if [ "$fetches" -ge 5 ]; then
        reasons="${reasons}fetch cap (5) reached; further entries unverified: $url"$'\n'; continue
      fi
      fetches=$((fetches+1))
      # The query string is part of the edge cache key: a 404 cached before the upload
      # (Cloudflare keeps it for hours) must not fail the check after it.
      if ! got="$($PROOF_ASSET_FETCH "$url?kit-check=$(date +%s)" 2>/dev/null | shasum -a 256 | awk '{print $1}')"; then
        reasons="${reasons}fetch failed: $url"$'\n'; continue
      fi
      [ "$got" = "$sha" ] && return 0
      reasons="${reasons}hash mismatch: $url"$'\n'
    done < <(jq -r '.assets[]? | [(.status // ""), (.url // ""), (.sha256 // ""), (.file // ""), (.bytes // "")] | join("\u001f")' "$mfile" 2>/dev/null)
  done <<< "$manifests"

  {
    echo "BLOCKED: visual proof of done. The branch changes UI files; its proof needs one qualifying image:"
    if [ -n "$reasons" ]; then
      printf '%s' "$reasons" | awk '!seen[$0]++' | sed 's/^/  /'
    else
      echo "  no image: no committed image link, no verified uploaded asset, no cached local asset."
    fi
    [ "$pending" -eq 1 ] && echo "  run \`bin/proof-asset flush\` to upload pending entries, then re-push."
    echo "  Add one: 'bin/proof-asset put <slug> <image>' prints the ![name](url) line to paste into the proof file, or commit the image and embed it."
  } >&2
  return 1
}

check() {
  local root="${1:-}" base="${2:-}" slug="${3:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: check <root> <base> [slug]" >&2; return 64; }
  # fail open: base must resolve to a real commit.
  git -C "$root" rev-parse --verify -q "$base" >/dev/null 2>&1 || return 0

  local class last_v; class="$(classify "$root" "$base")"
  [ "$class" = "inert" ] && return 0          # docs/cosmetic: no ritual.
  local negctl_req=yes
  [ "$class" = "behavioral" ] && negctl_req="$(_negctl_required "$root" "$base" "$slug")"

  # The image rule (R1/R2): a separate yes/no, never folded into classify()'s output.
  # visual=yes needs all three: proof.visual resolves true, the class is behavioral,
  # and a changed file carries a UI extension. stateful and inert diffs never get the
  # image rule; visual=no leaves every line below byte-identical to master.
  # The project layer counts only when .kit.toml is tracked and clean: an uncommitted
  # edit leaves no trace in the PR, so it can neither arm the rule for an attacker
  # nor disarm an operator's own opt-in. Otherwise only operator/kit-root files count.
  local visual=no
  if [ "$class" = "behavioral" ] \
     && [ -n "$(_changed "$root" "$base" | grep -E '\.(tsx|jsx|vue|svelte|css|scss|html)$')" ]; then
    if kit_config_tracked_clean "$root/.kit.toml"; then
      [ "$(KIT_PROJECT_ROOT="$root" kit_config_get proof.visual false 2>/dev/null)" = "true" ] && visual=yes
    else
      [ "$(kit_config_get_root proof.visual false 2>/dev/null)" = "true" ] && visual=yes
    fi
  fi

  local files f ok=1
  # near_miss: one "path<TAB>last_v" line per behavioral file/group that has a
  # NEGATIVE CONTROL and a green run but is rejected solely because its own FINAL Verdict
  # line reads FAIL/INCONCLUSIVE , read only on the BLOCKED path below, never touches ok.
  # no_output: one path per file/group with no captured output and no committed image; read
  # only on the BLOCKED path, which names what to add.
  local near_miss="" no_output="" has_negctl has_green has_out last_ok
  # A run counts only with its CAPTURED OUTPUT: a green marker (Exit: 0 / Verdict: PASS) is a
  # typed claim, so it needs real lines under an `Output:` slot (see _captured_output).
  # A committed screenshot/GIF embed counts as captured run-evidence too (visual/demo work
  # proves "it actually ran" with a picture, not only a text run-table). The semantic marker
  # (NEGATIVE CONTROL / rollback) is still required, and the image must actually EXIST , see
  # _has_committed_image, so a dangling `![x](missing.gif)` reference does not count.
  files="$(_fresh_proof_files "$root" "$base")"
  # per-file (back-compat): a flat docs/verification/<slug>.md or a co-located
  # proof-of-done.md carries both markers in one file.
  if [ -n "$files" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      local p="$root/$f"; [ -f "$p" ] || continue
      has_out=1; { _has_captured_output < "$p" || _has_committed_image "$p" "$root"; } && has_out=0
      [ "$has_out" -eq 0 ] || no_output="${no_output}${f}"$'\n'
      if [ "$class" = "behavioral" ]; then
        # An INCONCLUSIVE verdict never satisfies the gate, even with Exit: 0.
        # LAST-verdict-wins (review lens 2): the documented append shape retries after a
        # noisy run, so only the most recent Verdict: line in the file decides.
        last_v="$(grep -iE '^[[:space:]]*Verdict:' "$p" | tail -1)"
        has_negctl=1; { [ "$negctl_req" = no ] || grep -qi 'NEGATIVE CONTROL' "$p"; } && has_negctl=0
        has_green=1; [ "$has_out" -eq 0 ] && { grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS' "$p" || _has_committed_image "$p" "$root"; } && has_green=0
        last_ok=1; ! printf '%s' "$last_v" | grep -qiE 'Verdict:[[:space:]]*(INCONCLUSIVE|FAIL)' && last_ok=0
        if [ "$has_negctl" -eq 0 ] && [ "$has_green" -eq 0 ] && [ "$last_ok" -eq 0 ]; then
          ok=0; break
        fi
        if [ "$has_negctl" -eq 0 ] && [ "$has_green" -eq 0 ] && [ "$last_ok" -ne 0 ]; then
          near_miss="${near_miss}${f}$(printf '\t')${last_v}"$'\n'
        fi
      else # stateful
        # [UNAVAILABLE: reason] says no run was possible, so it owes no output.
        grep -qiE 'rollback|\[UNAVAILABLE' "$p" && { [ "$has_out" -eq 0 ] || grep -qi '\[UNAVAILABLE' "$p"; } \
          && { grep -qE 'Command:|Exit:' "$p" || _has_committed_image "$p" "$root"; } && ok=0 && break
      fi
    done <<< "$files"
  fi
  # set-wise (directory layout): under docs/verification/<slug>/ the green run and the
  # negative control may live in different runs/ files. Group by the <slug>/ prefix and
  # satisfy when the UNION of a group's files carries both markers.
  if [ "$ok" -ne 0 ] && [ -n "$files" ]; then
    local groups g content grp_img
    groups="$(printf '%s\n' "$files" | sed -nE 's#^(.*docs/verification/[^/]+/).*#\1#p' | sort -u)"
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      content=""; grp_img=1     # grp_img=0 iff some file in the group embeds a REAL image
      while IFS= read -r f; do
        case "$f" in
          "$g"*) [ -f "$root/$f" ] && { content+="$(cat "$root/$f")"$'\n'; _has_committed_image "$root/$f" "$root" && grp_img=0; } ;;
        esac
      done <<< "$(printf '%s\n' "$files" | sort)"
      has_out=1; { printf '%s' "$content" | _has_captured_output || [ "$grp_img" -eq 0 ]; } && has_out=0
      # A group's union can hold the output its single files lack, so the group replaces them.
      [ "$has_out" -eq 0 ] && no_output="$(printf '%s' "$no_output" | awk -v g="$g" 'index($0, g) != 1')"$'\n'
      if [ "$class" = "behavioral" ]; then
        # Last-verdict-wins, set-wise: files concatenate in sorted (= chronological)
        # order, so the union's final Verdict: line is the latest run's.
        last_v="$(printf '%s' "$content" | grep -iE '^[[:space:]]*Verdict:' | tail -1)"
        has_negctl=1; { [ "$negctl_req" = no ] || grep -qi 'NEGATIVE CONTROL' < <(printf '%s' "$content"); } && has_negctl=0
        has_green=1; [ "$has_out" -eq 0 ] && { grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS' < <(printf '%s' "$content") || [ "$grp_img" -eq 0 ]; } && has_green=0
        last_ok=1; ! printf '%s' "$last_v" | grep -qiE 'Verdict:[[:space:]]*(INCONCLUSIVE|FAIL)' && last_ok=0
        if [ "$has_negctl" -eq 0 ] && [ "$has_green" -eq 0 ] && [ "$last_ok" -eq 0 ]; then
          ok=0; break
        fi
        # near-miss dedupe: a per-file near miss already recorded for a member of this group
        # covers the same underlying issue, so the group rollup is not reported a second time.
        if [ "$has_negctl" -eq 0 ] && [ "$has_green" -eq 0 ] && [ "$last_ok" -ne 0 ] \
           && ! printf '%s' "$near_miss" | cut -f1 | grep -qF "$g"; then
          near_miss="${near_miss}${g}$(printf '\t')${last_v}"$'\n'
        fi
      else # stateful
        grep -qiE 'rollback|\[UNAVAILABLE' < <(printf '%s' "$content") \
          && { [ "$has_out" -eq 0 ] || grep -qi '\[UNAVAILABLE' < <(printf '%s' "$content"); } \
          && { grep -qE 'Command:|Exit:' < <(printf '%s' "$content") || [ "$grp_img" -eq 0 ]; } \
          && ok=0 && break
      fi
    done <<< "$groups"
  fi
  # R3: a visual=yes diff owes one qualifying image on top of every existing rule, so the
  # pass below is gated on it. _visual_proof prints the block message itself when nothing
  # qualifies. A failed visual check downgrades ok to 1 rather than returning, so the
  # logged-override fallback below clears a visual block the same way it clears an
  # unproven diff (with the same docs/deploy-inert-only restriction). With the rule off
  # (visual=no) this check is inert; the return line keeps its exact form because
  # test-proof-override-order.sh builds its pre-fix lib by deleting it.
  local visual_block=0
  if [ "$ok" -eq 0 ] && [ "$visual" = yes ] && ! _visual_proof "$root" "$base"; then
    visual_block=1; ok=1
  fi
  [ "$ok" -eq 0 ] && return 0

  # A real proof (checked above) always wins outright. Only fall back to an override
  # when no fresh proof file satisfies the requirement: the override log is append-only,
  # so checking it FIRST (the old order) meant a mistaken or early override for a slug
  # touching a source file blocked that slug FOREVER, even after a legitimate
  # proof-of-done with a NEGATIVE CONTROL landed in the same branch later (found
  # 2026-08-06: a docs+one-line-.sh-fix branch logged an override before writing its
  # proof doc, then could never pass again once the proof doc existed, because this
  # check short-circuited on the override every time). Checking the real proof first
  # closes that trap without weakening the override's own docs-only restriction below.
  if [ -n "$slug" ] && is_overridden "$slug" "$root"; then
    # cc-hyg-04: an override excuses docs / deploy-inert work, NOT application source
    # code. A blanket override that silently passes an unproven SOURCE change is the
    # rtk-611 hole (2026-07-01: an overridden branch shipped a broken source change,
    # reverted 9h later). Deploy scripts under a deploy/ path stay override-able (they
    # are verified via deploy-proof/UAT); source code elsewhere is not.
    # Build the source-code remainder. A file counts as source if it has a code
    # extension OR is an extensionless shebang script (e.g. the kit's own
    # lib/goal/handoff-gen); deploy scripts at a SANCTIONED location (repo-root deploy/
    # or a per-tool tools/<name>/deploy/) are exempt -- but a `deploy` dir nested
    # anywhere else (src/deploy/, lib/deploy/) is NOT, or it would reopen the hole.
    local src_remainder="" f
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in deploy/*|tools/*/deploy/*) continue ;; esac   # sanctioned deploy: override-able
      if printf '%s' "$f" | grep -qE '\.(sh|bash|zsh|py|js|jsx|mjs|cjs|ts|tsx|go|rs|rb|c|h|cc|cpp|hpp|java|php|swift|kt|kts|scala|clj|cljs|ex|exs|lua|pl|pm|r|m|mm|sql)$'; then
        src_remainder="${src_remainder}${f}"$'\n'; continue
      fi
      # extensionless file (no dot in basename): treat as source if it is a shebang script.
      case "$(basename "$f")" in
        *.*) : ;;
        *) [ -f "$root/$f" ] && [ "$(head -c2 "$root/$f" 2>/dev/null)" = '#!' ] && src_remainder="${src_remainder}${f}"$'\n' ;;
      esac
    done < <(_changed "$root" "$base")
    if [ -n "$src_remainder" ]; then
      echo "proof-of-done: override for '$slug' REJECTED -- the branch changes source files with no proof of done:" >&2
      printf '%s' "$src_remainder" | sed 's/^/    - /' >&2
      echo "  An override excuses docs / deploy-inert work only. Provide a proof of done for the source change (run /kit:verify), or split it out." >&2
      return 1
    fi
    echo "proof-of-done: OVERRIDDEN for '$slug' (docs/deploy-inert remainder; logged, see $OVERRIDE_LOG)" >&2
    return 0
  fi

  # A visual block already printed its own named reasons; only the escape route remains.
  if [ "$visual_block" -eq 1 ]; then
    echo "  Or clear it with an audited override (docs/deploy-inert remainder only):" >&2
    echo "    bash lib/gate/proof-ledger.sh override '${slug:-<branch-slug>}' \"<reason>\"" >&2
    return 1
  fi

  # blocked: name exactly what is missing.
  {
    echo "BLOCKED: proof of done. This is a '$class' change; it cannot ship/merge without a matching proof-of-done entry in docs/verification/."
    if [ "$class" = "behavioral" ]; then
      if [ "$negctl_req" = no ]; then
        echo "  Need: a docs/verification/<slug>.md added by this branch with a green run ([gate] negative_control = full: no NEGATIVE CONTROL owed for this non-hard-path diff)."
      else
        echo "  Need: a docs/verification/<slug>.md added by this branch with a green run AND a NEGATIVE CONTROL (revert -> RED -> restore)."
      fi
      echo "        ('green run' = a text run-table (Command:/Exit:/Output:/Verdict: PASS) with the run's real output under Output: (or after Exit: inside the run's fenced block), OR a committed screenshot/GIF embed for visual/demo work.)"
      # A file that IS found and carries a NEGATIVE CONTROL + a green run, but is
      # rejected solely because its own final Verdict line reads FAIL/INCONCLUSIVE, gets named
      # here instead of vanishing into the generic message above.
      if [ -n "$near_miss" ]; then
        local nm_f nm_v
        while IFS=$'\t' read -r nm_f nm_v; do
          [ -n "$nm_f" ] || continue
          echo "  Hint: $nm_f has a NEGATIVE CONTROL and a green run, but its LAST Verdict line reads FAIL/INCONCLUSIVE (\"$nm_v\"). The gate reads the file's FINAL Verdict line as the outcome: record the negative control's own outcome as \`Result: RED as expected\` (not \`Verdict:\`), and end the file on \`Verdict: PASS\` after the real run (the shape lib/gate/negctl.sh itself emits: \`Exit: 0\` / \`Verdict: PASS\` are the two valid \"green run\" spellings this gate already accepts)."
        done <<< "$near_miss"
      fi
    else
      echo "  Need: a docs/verification/<slug>.md added by this branch with a recorded run AND a rollback note, or [UNAVAILABLE: reason] if no such flow exists here."
      echo "        ('recorded run' = Command:/Exit:/Output: text with the run's real output under Output:, OR a committed screenshot/GIF embed for visual/demo work.)"
    fi
    # A proof file that IS found but shows nothing the run printed: name the slot to add.
    if [ -n "$no_output" ]; then
      local no_f
      while IFS= read -r no_f; do
        [ -n "$no_f" ] || continue
        echo "  Hint: $no_f has no captured output: a typed Exit: 0 or Verdict: PASS is a claim, not evidence. Add an \`Output:\` line to the run block and paste under it what the run really printed (the test recap, the tail of the run); a slot left empty or holding only a <placeholder> does not count. For visual work embed a committed screenshot or GIF instead: \`![after](shot.png)\`."
      done <<< "$no_output"
    fi
    echo "  Type-specific shape: run 'bash lib/gate/proof-gate.sh contract \"<your task>\"' for the exact artifact this work-type owes + the skill that owns it (e.g. a data/CLI tool owes a recorded live run; an eval owes a TEST-REPORT)."
    echo "  Produce it via /kit:verify (or record it), or log an explicit override (audited):"
    echo "    bash lib/gate/proof-ledger.sh override '${slug:-<branch-slug>}' \"<reason>\""
    echo "  Or switch this gate off for the repo: [gate] proof_of_done = false in a committed .kit.toml (lib/gate/README.md, 'Switching a gate off')."
    # Operator hint: an override for THIS slug exists in the log but is scoped to a
    # different repo (legacy unqualified, a sibling repo, or a non-root/wrong-worktree cwd),
    # so it does not apply here. Say so, or the operator re-logs and it still "does nothing".
    if [ -n "$slug" ] && [ -f "$OVERRIDE_LOG" ] \
       && awk -F'|' -v s="$slug" 'function trim(x){gsub(/^[ \t]+|[ \t]+$/,"",x);return x} trim($3)==s && trim($4)=="OVERRIDE"{f=1;exit} END{exit(f?0:1)}' "$OVERRIDE_LOG"; then
      echo "  Note: an override for '$slug' exists in the log but is scoped to a different repo; re-log it from THIS repo's root."
    fi
  } >&2
  return 1
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  classify)      classify "$@" ;;
  check)         check "$@" ;;
  override)      override "$@" ;;
  is-overridden) is_overridden "$@" ;;
  proof-files)   [ $# -ge 2 ] || { echo "usage: proof-files <root> <base>" >&2; exit 64; }; _fresh_proof_files "$@" ;;
  captured-output) [ -f "${1:-}" ] || { echo "usage: captured-output <proof-file>" >&2; exit 64; }; _captured_output < "$1" ;;
  images)        [ $# -ge 2 ] || { echo "usage: images <proof-file> <root>" >&2; exit 64; }; _committed_images "$@" ;;
  deployable)    deployable "$@" ;;
  delivery-ratio) delivery_ratio "$@" ;;
  negctl)        negctl "$@" ;;
  *) echo "usage: proof-ledger.sh {classify|check|override|is-overridden|proof-files|captured-output|images|deployable|delivery-ratio|negctl} ..." >&2; exit 64 ;;
esac
