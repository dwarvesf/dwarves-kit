#!/usr/bin/env bash
# promote.sh: the trusted promote core. This (via bin/skill-review) is the ONLY writer of
# ~/.claude/skills/ , the background reviewer never is. Sourced by bin/skill-review and the tests.
#
# promote_list                  list staged drafts (slug + description)
# promote_one <slug> [--force]  move skill-proposals/<slug> -> skills/<slug>; refuse to overwrite a
#                               live skill without --force; refuse a draft that still has a secret
# promote_reject <slug>         move the draft to skill-proposals/_rejected/ (never rm)
# auto_promote_eligible <slug>  true ONLY for the lowest-risk class (references-add to an existing
#                               umbrella); used by the optional auto_promote knob
# promote_auto                  if config auto_promote=on, auto-pass only the eligible drafts

HERE_PROMOTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE_PROMOTE/common.sh"

# Reserved proposal subdirs that are not drafts.
_is_reserved() { case "$1" in _rejected|_replaced|_archive) return 0;; *) return 1;; esac; }

_desc_of() {  # read `description:` from a SKILL.md frontmatter, else ""
  local f="$1"; [ -f "$f" ] || { printf ''; return; }
  sed -n 's/^description:[[:space:]]*//p' "$f" | head -1
}

promote_list() {
  [ -d "$CC_SI_PROPOSALS_DIR" ] || { echo "(no staged drafts)"; return 0; }
  local found=0 d slug
  for d in "$CC_SI_PROPOSALS_DIR"/*/; do
    [ -d "$d" ] || continue
    slug="$(basename "$d")"; _is_reserved "$slug" && continue
    [ -f "$d/SKILL.md" ] || continue
    found=1
    printf '%s\t%s\n' "$slug" "$(_desc_of "$d/SKILL.md")"
  done
  [ "$found" = 1 ] || echo "(no staged drafts)"
}

promote_one() {
  local slug="${1:-}" force=0; [ "${2:-}" = "--force" ] && force=1
  [ -n "$slug" ] || { echo "promote: need a slug" >&2; return 2; }
  local src="$CC_SI_PROPOSALS_DIR/$slug" dest="$CC_SI_SKILLS_DIR/$slug"
  [ -d "$src" ] && [ -f "$src/SKILL.md" ] || { echo "promote: no draft '$slug'" >&2; return 2; }

  if contains_secret "$(cat "$src/SKILL.md" 2>/dev/null)"; then
    echo "promote: REFUSED '$slug' , SKILL.md contains a secret-shaped string; scrub it first" >&2
    si_log "promote refused (secret): $slug"; return 3
  fi
  if [ -e "$dest" ] && [ "$force" != 1 ]; then
    echo "promote: REFUSED , '$slug' already exists under skills/; re-run with --force to replace" >&2
    return 4
  fi
  mkdir -p "$CC_SI_SKILLS_DIR" 2>/dev/null || { echo "promote: cannot create $CC_SI_SKILLS_DIR" >&2; return 5; }
  if [ -e "$dest" ] && [ "$force" = 1 ]; then   # back up the live skill before replacing (never rm)
    local bak
    bak="$CC_SI_PROPOSALS_DIR/_replaced/${slug}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$(dirname "$bak")" 2>/dev/null || true
    mv "$dest" "$bak" 2>/dev/null && si_log "promote --force: backed up live skill -> $bak"
  fi
  mv "$src" "$dest" 2>/dev/null || { echo "promote: move failed" >&2; return 5; }
  echo "promote: '$slug' -> $dest"
  si_log "promote: $slug -> skills/"
}

promote_reject() {
  local slug="${1:-}"; [ -n "$slug" ] || { echo "reject: need a slug" >&2; return 2; }
  local src="$CC_SI_PROPOSALS_DIR/$slug"
  [ -d "$src" ] || { echo "reject: no draft '$slug'" >&2; return 2; }
  local dest="$CC_SI_PROPOSALS_DIR/_rejected/$slug"
  mkdir -p "$(dirname "$dest")" 2>/dev/null || true
  [ -e "$dest" ] && dest="${dest}-$(date +%Y%m%d-%H%M%S)"
  mv "$src" "$dest" 2>/dev/null || { echo "reject: move failed" >&2; return 5; }
  echo "reject: '$slug' -> _rejected/ (recoverable, not deleted)"
  si_log "reject: $slug -> _rejected/"
}

# auto_promote_eligible <slug>: the ONLY auto-passable class. The draft must explicitly mark itself
# a references-add (`cc-si-kind: references-add`) into an umbrella that ALREADY EXISTS under skills/,
# name a `references/<topic>.md` target path, and pass the secret scan. Never a new skill, never a
# SKILL.md-body edit. 02's reviewer does not emit this yet; the predicate is the safe gate for when
# it does.
auto_promote_eligible() {
  local slug="${1:-}" f="$CC_SI_PROPOSALS_DIR/${1:-}/SKILL.md"
  [ -f "$f" ] || return 1
  local kind umb path
  kind="$(sed -n 's/^cc-si-kind:[[:space:]]*//p' "$f" | head -1)"
  umb="$(sed -n 's/^cc-si-umbrella:[[:space:]]*//p' "$f" | head -1)"
  path="$(sed -n 's/^cc-si-path:[[:space:]]*//p' "$f" | head -1)"
  [ "$kind" = "references-add" ] || return 1
  [ -n "$umb" ] && [ -d "$CC_SI_SKILLS_DIR/$umb" ] || return 1     # umbrella must already exist
  case "$path" in references/*.md) : ;; *) return 1;; esac        # references-only, no traversal
  case "$path" in *..*) return 1;; esac
  contains_secret "$(cat "$f" 2>/dev/null)" && return 1
  return 0
}

promote_auto() {
  [ "$(cfg auto_promote false)" = "true" ] || { echo "auto-promote: disabled (auto_promote=false)"; return 0; }
  local d slug umb path n=0
  for d in "$CC_SI_PROPOSALS_DIR"/*/; do
    [ -d "$d" ] || continue; slug="$(basename "$d")"; _is_reserved "$slug" && continue
    auto_promote_eligible "$slug" || continue
    umb="$(sed -n 's/^cc-si-umbrella:[[:space:]]*//p' "$d/SKILL.md" | head -1)"
    path="$(sed -n 's/^cc-si-path:[[:space:]]*//p' "$d/SKILL.md" | head -1)"
    mkdir -p "$CC_SI_SKILLS_DIR/$umb/$(dirname "$path")" 2>/dev/null || continue
    cp "$d/SKILL.md" "$CC_SI_SKILLS_DIR/$umb/$path" 2>/dev/null && {
      promote_reject "$slug" >/dev/null    # clear the draft once absorbed
      echo "auto-promote: $slug -> skills/$umb/$path"; si_log "auto-promote: $slug -> $umb/$path"; n=$((n+1)); }
  done
  echo "auto-promote: $n promoted"
}
