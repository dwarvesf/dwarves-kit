#!/usr/bin/env bash
# test-ceremony-fits-diff.sh -- the ceremony a diff owes follows what the diff changes.
#   1. Proof class (lib/gate/proof-ledger.sh classify/check): a diff made only of docs owes no proof.
#      Docs = *.md/*.txt anywhere, .kit.toml, and any file under a docs/ tree whatever its extension
#      (a generated .html/.svg/.png drawing set holds JS and images but ships no behavior).
#   2. Hard-path floor (lib/classify/lane-classify.sh floor, ship_rule_floor in lib/gate/ship-rules.sh):
#      a hard-path hit counts only for a non-doc file whose hunks change more than comment or blank
#      lines. Anything the check cannot prove keeps the floor.
# Each case prints `PASS <name>` or `FAIL <name>: <why>`; the file exits nonzero on any FAIL.
# Run: bash tests/test-ceremony-fits-diff.sh [case ...]
# Negative control: PROOF_LEDGER_LIB / LANE_CLASSIFY_LIB point the suite at an older lib.

set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PL="${PROOF_LEDGER_LIB:-$KIT/lib/gate/proof-ledger.sh}"
LC="${LANE_CLASSIFY_LIB:-$KIT/lib/classify/lane-classify.sh}"
SR="$KIT/lib/gate/ship-rules.sh"

FAILS=0; TMPS=()
_mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS+1)); }

ROOT=""
_git() { git -C "$ROOT" -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
_commit() { _git add -A -f >/dev/null 2>&1; _git commit -q -m "${1:-chore: change}" >/dev/null 2>&1; }
put() { mkdir -p "$(dirname "$ROOT/$1")"; printf '%s\n' "$2" > "$ROOT/$1"; }
# mkrepo: main with a committed .kit.toml (lane_gates on), then `base <path> <content>` files, then `branch`.
mkrepo() {
  ROOT="$(_mk)"
  git init -q -b main "$ROOT" >/dev/null 2>&1
  git -C "$ROOT" config user.email t@users.noreply.github.com; git -C "$ROOT" config user.name t
  printf '[gate]\nlane_gates = true\n' > "$ROOT/.kit.toml"
  echo hi > "$ROOT/README.md"
}
base() { put "$1" "$2"; }
branch() { _commit "chore: base"; _git checkout -q -b feat/x >/dev/null 2>&1; }
# KIT_CONFIG_OPERATOR=/nonexistent: no operator overlay is read.
lcx() { env KIT_CONFIG_OPERATOR=/nonexistent bash "$LC" "$@"; }
floor_out() { lcx floor "$ROOT" main 2>/dev/null; }
cls() { env KIT_CONFIG_OPERATOR=/nonexistent bash "$PL" classify "$ROOT" "$(git -C "$ROOT" rev-parse main)"; }

# ---------------------------------------------------------------------------
# 1. Proof class
# ---------------------------------------------------------------------------
HTML_JS='<!doctype html><script>document.title = "drawing"; fetch("/x")</script><svg><rect/></svg>'

case_class_docs_tree_any_extension_is_inert() {
  local bad="" p got
  for p in docs/design/uml.html docs/design/sheet.svg docs/img/a.png docs/data/x.json tools/x/docs/notes.pdf; do
    mkrepo; base docs/README.md base; branch
    put "$p" "$HTML_JS"; _commit "feat: generated drawing set"
    got="$(cls)"; [ "$got" = inert ] || bad="$bad [$p => $got]"
  done
  [ -z "$bad" ] && pass class-docs-tree-any-extension-is-inert || fail class-docs-tree-any-extension-is-inert "$bad"
}

# Source code and secret-shaped files do not become docs by living under docs/.
case_class_code_under_docs_keeps_its_class() {
  local bad="" p got
  for p in docs/design/app.js tools/x/docs/run.sh src/docs/h.py docs/credentials.json docs/secrets/notes.png; do
    mkrepo; base docs/README.md base; branch
    put "$p" "x"; _commit "feat: change"
    got="$(cls)"; [ "$got" = behavioral ] || bad="$bad [$p => $got]"
  done
  [ -z "$bad" ] && pass class-code-under-docs-keeps-its-class || fail class-code-under-docs-keeps-its-class "$bad"
}

case_class_docs_subject_words_ignored() {
  mkrepo; base docs/README.md base; branch
  put docs/design/migrations.html "$HTML_JS"; _commit "docs: migrate the deploy drawing set to the new database schema"
  local got; got="$(cls)"
  [ "$got" = inert ] && pass class-docs-subject-words-ignored || fail class-docs-subject-words-ignored "got $got"
}

case_class_markdown_anywhere_is_inert() {
  mkrepo; base src/NOTES.md a; branch
  put src/NOTES.md b; put lib/deep/README.md c; _commit "docs: notes"
  local got; got="$(cls)"
  [ "$got" = inert ] && pass class-markdown-anywhere-is-inert || fail class-markdown-anywhere-is-inert "got $got"
}

case_class_other_files_keep_class() {
  local bad="" p got
  for p in site/docs.html src/app.js lib/y.sh docsite/x.html; do
    mkrepo; base docs/README.md base; branch
    put "$p" "$HTML_JS"; _commit "feat: change"
    got="$(cls)"; [ "$got" = behavioral ] || bad="$bad [$p => $got]"
  done
  mkrepo; base docs/README.md base; branch
  put lib/deploy.sh 'echo hi'; _commit "feat: change"; got="$(cls)"
  [ "$got" = stateful ] || bad="$bad [lib/deploy.sh => $got]"
  [ -z "$bad" ] && pass class-other-files-keep-class || fail class-other-files-keep-class "$bad"
}

case_class_docs_plus_code_follows_code() {
  mkrepo; base docs/README.md base; branch
  put docs/design/uml.html "$HTML_JS"; put lib/y.sh 'echo hi'; _commit "feat: change"
  local got; got="$(cls)"
  [ "$got" = behavioral ] && pass class-docs-plus-code-follows-code || fail class-docs-plus-code-follows-code "got $got"
}

case_check_docs_tree_owes_no_proof() {
  mkrepo; base docs/README.md base; branch
  put docs/design/uml.html "$HTML_JS"; _commit "feat: generated drawing set"
  local out rc
  out="$(env KIT_CONFIG_OPERATOR=/nonexistent bash "$PL" check "$ROOT" "$(git -C "$ROOT" rev-parse main)" some-slug 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ] && pass check-docs-tree-owes-no-proof || fail check-docs-tree-owes-no-proof "rc=$rc out=$out"
}

# ---------------------------------------------------------------------------
# 2. Hard-path floor
# ---------------------------------------------------------------------------
# Every base ends with a comment line: a comment-only change group must follow a comment, a blank line or the top of the file.
PYBASE=$'import os\n\ndef login(user):\n    return check(user)\n# end'
SHBASE=$'#!/bin/bash\nset -e\nrun_migration\n# end'

expect() {  # expect <name> <hit|miss> [<path-that-must-be-named>]
  local name="$1" want="$2" path="${3:-}" out; out="$(floor_out)"
  if [ "$want" = hit ]; then
    case "$out" in "full "*"${path:+: $path}") pass "$name" ;; *) fail "$name" "wanted a hit${path:+ on $path}, got '$out'" ;; esac
  else
    [ -z "$out" ] && pass "$name" || fail "$name" "wanted no hit, got '$out'"
  fi
}

case_floor_docs_never_hit() {
  local bad="" p out
  for p in docs/auth/design.md docs/design/auth-flow.html docs/auth/flows.json \
           db/migrations/README.md src/auth/README.txt .github/README.md notes/login.md; do
    mkrepo; branch; put "$p" "x"; _commit "docs: add"
    out="$(floor_out)"; [ -z "$out" ] || bad="$bad [$p => '$out']"
  done
  [ -z "$bad" ] && pass floor-docs-never-hit || fail floor-docs-never-hit "$bad"
}

# Only documentation and asset extensions count under docs/. Code, config and SQL there, and code that
# borrows a doc name, keep the floor.
case_floor_code_under_docs_or_doc_named_still_hits() {
  local bad="" p out
  for p in docs/migrations/0001.sql .github/docs/ci.yml src/auth/docs/check.py src/docs/login.py \
           .github/workflows/README.yml db/migrations/README.sql src/auth/README.sh docs/auth/run.sh \
           src/auth/docs/login.html src/auth/docs/x.svg .github/actions/docs/package.json db/migrations/docs/001.json \
           docs/credentials.json docs/secrets/notes.png; do
    mkrepo; branch; put "$p" "x"; _commit "feat: add"
    out="$(floor_out)"; case "$out" in "full "*": $p") ;; *) bad="$bad [$p => '$out']" ;; esac
  done
  [ -z "$bad" ] && pass floor-code-under-docs-or-doc-named-still-hits || fail floor-code-under-docs-or-doc-named-still-hits "$bad"
}

case_floor_docs_beside_real_hard_path_still_hit() {
  mkrepo; branch; put docs/auth/design.md x; put db/migrations/0001_users.sql 'create table users (id int);'; _commit "feat: both"
  expect floor-docs-beside-real-hard-path-still-hit hit db/migrations/0001_users.sql
}

case_floor_comment_only_edit_is_not_a_hit() {
  local bad="" p content out
  while IFS='|' read -r p content; do
    [ -n "$p" ] || continue
    case "$content" in PY) content="$PYBASE" ;; SH) content="$SHBASE" ;; *) content="$content"$'\n# end' ;; esac
    mkrepo; base "$p" "$content"; branch
    printf '# a new comment\n\n    # indented comment\n' >> "$ROOT/$p"; _commit "docs: comment"
    out="$(floor_out)"; [ -z "$out" ] || bad="$bad [$p => '$out']"
  done <<'CASES'
src/auth/login.py|PY
scripts/login.sh|SH
db/migrations/run.sh|SH
.github/workflows/ci.yml|on: push
.kit.toml|[gate]
terraform/iam.tf|resource "x" "y" {}
Dockerfile|FROM alpine
CASES
  [ -z "$bad" ] && pass floor-comment-only-edit-is-not-a-hit || fail floor-comment-only-edit-is-not-a-hit "$bad"
}

case_floor_comment_removal_is_not_a_hit() {
  mkrepo; base src/auth/login.py $'# old note\nimport os\n\ndef login(user):\n    return check(user)'; branch
  put src/auth/login.py $'import os\n\ndef login(user):\n    return check(user)'; _commit "docs: drop comment"
  expect floor-comment-removal-is-not-a-hit miss
}

case_floor_code_change_is_a_hit() {
  local bad="" kind out
  for kind in append-code replace-line delete-line comment-plus-code trailing-comment shebang; do
    mkrepo; base scripts/login.sh "$SHBASE"; branch
    case "$kind" in
      append-code)       printf 'echo changed\n' >> "$ROOT/scripts/login.sh" ;;
      replace-line)      put scripts/login.sh $'#!/bin/bash\nset -e\nrun_other' ;;
      delete-line)       put scripts/login.sh $'#!/bin/bash\nset -e' ;;
      comment-plus-code) printf '# note\nrm -rf x\n' >> "$ROOT/scripts/login.sh" ;;
      trailing-comment)  put scripts/login.sh $'#!/bin/bash\nset -e  # now loud\nrun_migration' ;;
      shebang)           put scripts/login.sh $'#!/bin/sh\nset -e\nrun_migration' ;;
    esac
    _commit "fix: change"
    out="$(floor_out)"
    [ "$out" = "full auth: scripts/login.sh" ] || bad="$bad [$kind => '$out']"
  done
  # a blank line right after a comment is not a behavior change; one after a code line might sit inside a string
  mkrepo; base scripts/login.sh "$SHBASE"; branch; put scripts/login.sh $'#!/bin/bash\n\nset -e\nrun_migration\n# end'; _commit "style: blank"
  out="$(floor_out)"; [ -z "$out" ] || bad="$bad [blank line => '$out']"
  [ -z "$bad" ] && pass floor-code-change-is-a-hit || fail floor-code-change-is-a-hit "$bad"
}

case_floor_cannot_decide_keeps_the_floor() {
  local bad="" out
  # a type with no known `#` syntax: a // comment in js stays a hit
  mkrepo; base src/auth/login.js $'const a = 1;'; branch; printf '// note\n' >> "$ROOT/src/auth/login.js"; _commit "docs: c"
  out="$(floor_out)"; [ "$out" = "full auth: src/auth/login.js" ] || bad="$bad [js => '$out']"
  # an exec-bit change with no content change
  mkrepo; base scripts/login.sh "$SHBASE"; branch; chmod +x "$ROOT/scripts/login.sh"; _commit "chore: chmod"
  out="$(floor_out)"; [ "$out" = "full auth: scripts/login.sh" ] || bad="$bad [chmod => '$out']"
  # a comment that steers a parser is code: Dockerfile directive, python coding tag
  mkrepo; base Dockerfile "FROM alpine"; branch; put Dockerfile $'# syntax=docker/dockerfile:1.7\nFROM alpine'; _commit "docs: c"
  out="$(floor_out)"; [ "$out" = "full infra: Dockerfile" ] || bad="$bad [dockerfile directive => '$out']"
  mkrepo; base src/auth/login.py "$PYBASE"; branch; put src/auth/login.py $'# -*- coding: latin-1 -*-\n'"$PYBASE"; _commit "docs: c"
  out="$(floor_out)"; [ "$out" = "full auth: src/auth/login.py" ] || bad="$bad [coding tag => '$out']"
  # a secret-kind path, even with a comment-only edit
  mkrepo; base secrets/rotate.sh "$SHBASE"; branch; printf '# note\n' >> "$ROOT/secrets/rotate.sh"; _commit "docs: c"
  out="$(floor_out)"; [ "$out" = "full secret: secrets/rotate.sh" ] || bad="$bad [secret => '$out']"
  # a binary file
  mkrepo; base src/auth/blob.py "$PYBASE"; branch; printf '\000\001\002# x\n' >> "$ROOT/src/auth/blob.py"; _commit "chore: bin"
  out="$(floor_out)"; [ "$out" = "full auth: src/auth/blob.py" ] || bad="$bad [binary => '$out']"
  # a symlink under a docs tree is not a doc
  mkrepo; branch; mkdir -p "$ROOT/docs/auth"; ln -s ../../.env "$ROOT/docs/auth/link"; _commit "chore: link"
  out="$(floor_out)"; [ "$out" = "full auth: docs/auth/link" ] || bad="$bad [symlink => '$out']"
  # a comment-only edit of a file that was deleted outright with real code still hits
  mkrepo; base db/migrations/0001.sh "$SHBASE"; branch; _git rm -q db/migrations/0001.sh; _commit "chore: rm"
  out="$(floor_out)"; [ "$out" = "full migration: db/migrations/0001.sh" ] || bad="$bad [delete code file => '$out']"
  # an empty diff of a path (touch only) is not in the diff at all; a new empty hard-path file has no hunk to prove
  mkrepo; branch; put src/auth/empty.py ""; : > "$ROOT/src/auth/empty.py"; _commit "chore: empty"
  out="$(floor_out)"; [ "$out" = "full auth: src/auth/empty.py" ] || bad="$bad [empty new file => '$out']"
  [ -z "$bad" ] && pass floor-cannot-decide-keeps-the-floor || fail floor-cannot-decide-keeps-the-floor "$bad"
}

case_floor_new_comment_only_file_is_not_a_hit() {
  mkrepo; branch; put src/auth/notes.py $'# only a note\n\n# another'; _commit "docs: note file"
  expect floor-new-comment-only-file-is-not-a-hit miss
}

case_floor_skips_comment_only_then_names_the_real_hit() {
  mkrepo; base src/auth/a.py "$PYBASE"; base src/auth/b.py "$PYBASE"; base src/auth/c.py "$PYBASE"; branch
  printf '# note\n' >> "$ROOT/src/auth/a.py"; printf 'x = 1\n' >> "$ROOT/src/auth/b.py"; printf '# note\n' >> "$ROOT/src/auth/c.py"; _commit "fix: mixed"
  expect floor-skips-comment-only-then-names-the-real-hit hit src/auth/b.py
}

# The loop is bounded (50 drops, 8 seconds): past either bound the floor stands. 51 files trip the count bound
# on a quiet host and the time bound on a loaded one, so the assertion holds on both. A handful drop quietly.
case_floor_cap_keeps_the_floor_on_a_flood() {
  local i n out bad=""
  for n in 3 51; do
    mkrepo
    for i in $(seq 1 "$n"); do base "db/migrations/m$i.sh" "$SHBASE"; done; branch
    for i in $(seq 1 "$n"); do printf '# note\n' >> "$ROOT/db/migrations/m$i.sh"; done; _commit "docs: comments"
    out="$(floor_out)"
    if [ "$n" = 3 ]; then [ -z "$out" ] || bad="$bad [3 comment-only files => '$out']"
    else case "$out" in "full migration: db/migrations/m"*) ;; *) bad="$bad [51 comment-only files => '$out']" ;; esac; fi
  done
  [ -z "$bad" ] && pass floor-cap-keeps-the-floor-on-a-flood || fail floor-cap-keeps-the-floor-on-a-flood "$bad"
}

# A `#` line can be data, and some comments are not comments: each of these keeps the floor.
case_floor_hash_that_is_not_a_comment_keeps_the_floor() {
  local bad="" kind out
  for kind in continuation heredoc triple yaml-block toml-string noqa shellcheck dockerfile-upper dockerfile-dir \
              sh-dq-string yaml-dq-scalar yaml-block-2 yaml-block-comment yaml-block-tag yaml-block-anchor hadolint tflint dockerfile-c after-code; do
    mkrepo
    case "$kind" in
      continuation)    base src/auth/hook.sh $'echo start \\\nrm -f victim' ;;
      heredoc)         base src/auth/hook.sh $'cat <<EOF\nalice\nEOF' ;;
      triple)          base src/auth/perm.py $'ALLOWED = """\nalice\n""".split()' ;;
      yaml-block)      base .github/workflows/ci.yml $'jobs:\n  a:\n    run: |\n      echo hi' ;;
      toml-string)     base .kit.toml $'x = """\nfoo\n"""' ;;
      noqa|shellcheck) base src/auth/perm.py $'x = 1\ny = 2' ;;
      dockerfile-upper) base Dockerfile 'FROM alpine' ;;
      dockerfile-dir)  base .github/actions/Dockerfile-lint/a.c 'int x;' ;;
      sh-dq-string)    base src/auth/users.sh $'A="\nalice\nbob\n"\n# end' ;;
      yaml-dq-scalar)  base .github/workflows/ci.yml $'A: "alice\n    bob"\n# end' ;;
      yaml-block-2)    base .github/workflows/ci.yml $'A: |2\n    alice\n\n    bob\n# end' ;;
      yaml-block-comment) base .github/workflows/ci.yml $'A: | # note\n    alice\n\n    bob\n# end' ;;
      yaml-block-tag)  base .github/workflows/ci.yml $'A: !!str |\n    alice\n\n    bob\n# end' ;;
      yaml-block-anchor) base .github/workflows/ci.yml $'A: &z |\n    alice\n\n    bob\n# end' ;;
      hadolint)        base Dockerfile $'FROM alpine\n# end' ;;
      tflint)          base infra/iam-policy.tf $'resource "a" "b" {}\n# end' ;;
      dockerfile-c)    base .github/actions/x/Dockerfile.c $'int x;\n# end' ;;
      after-code)      base src/auth/perm.py $'x = 1\ny = 2\n# end' ;;
    esac
    branch
    case "$kind" in
      continuation)    put src/auth/hook.sh $'echo start \\\n# note\nrm -f victim'; want="full auth: src/auth/hook.sh" ;;
      heredoc)         put src/auth/hook.sh $'cat <<EOF\nalice\n# eve\nEOF'; want="full auth: src/auth/hook.sh" ;;
      triple)          put src/auth/perm.py $'ALLOWED = """\nalice\n# eve\n""".split()'; want="full auth: src/auth/perm.py" ;;
      yaml-block)      put .github/workflows/ci.yml $'jobs:\n  a:\n    run: |\n      # mallory\n      echo hi'; want="full ci: .github/workflows/ci.yml" ;;
      toml-string)     put .kit.toml $'x = """\n# bar\nfoo\n"""'; want="full kit-config: .kit.toml" ;;
      noqa)            put src/auth/perm.py $'x = 1\n# noqa\ny = 2'; want="full auth: src/auth/perm.py" ;;
      shellcheck)      put src/auth/perm.py $'x = 1\n# shellcheck disable=SC2086\ny = 2'; want="full auth: src/auth/perm.py" ;;
      dockerfile-upper) put Dockerfile $'# SYNTAX=evil/frontend:1\nFROM alpine'; want="full infra: Dockerfile" ;;
      dockerfile-dir)  put .github/actions/Dockerfile-lint/a.c $'int x;\n#define AUTH_OFF 1'; want="full ci: .github/actions/Dockerfile-lint/a.c" ;;
      sh-dq-string)    put src/auth/users.sh $'A="\nalice\n# eve\nbob\n"\n# end'; want="full auth: src/auth/users.sh" ;;
      yaml-dq-scalar)  put .github/workflows/ci.yml $'A: "alice\n    # eve\n    bob"\n# end'; want="full ci: .github/workflows/ci.yml" ;;
      yaml-block-2)    put .github/workflows/ci.yml $'A: |2\n    alice\n\n    # eve\n    bob\n# end'; want="full ci: .github/workflows/ci.yml" ;;
      yaml-block-comment) put .github/workflows/ci.yml $'A: | # note\n    alice\n\n    # eve\n    bob\n# end'; want="full ci: .github/workflows/ci.yml" ;;
      yaml-block-tag)  put .github/workflows/ci.yml $'A: !!str |\n    alice\n\n    # eve\n    bob\n# end'; want="full ci: .github/workflows/ci.yml" ;;
      yaml-block-anchor) put .github/workflows/ci.yml $'A: &z |\n    alice\n\n    # eve\n    bob\n# end'; want="full ci: .github/workflows/ci.yml" ;;
      hadolint)        put Dockerfile $'FROM alpine\n# end\n# hadolint ignore=DL3008'; want="full infra: Dockerfile" ;;
      tflint)          put infra/iam-policy.tf $'resource "a" "b" {}\n# end\n# tflint-ignore: terraform_required_version'; want="full infra: infra/iam-policy.tf" ;;
      dockerfile-c)    put .github/actions/x/Dockerfile.c $'int x;\n# end\n#define X 1'; want="full ci: .github/actions/x/Dockerfile.c" ;;
      after-code)      put src/auth/perm.py $'x = 1\n# a note after code\ny = 2\n# end'; want="full auth: src/auth/perm.py" ;;
    esac
    _commit "docs: c"
    out="$(floor_out)"; [ "$out" = "$want" ] || bad="$bad [$kind => '$out' want '$want']"
  done
  [ -z "$bad" ] && pass floor-hash-that-is-not-a-comment-keeps-the-floor || fail floor-hash-that-is-not-a-comment-keeps-the-floor "$bad"
}

# A path that matches the secret pattern never softens, even when an earlier kind (auth) reports it first.
case_floor_secret_pattern_beats_first_kind() {
  local bad="" p out
  for p in src/auth/secrets/rotate.sh infra/auth/credentials.toml; do
    mkrepo; base "$p" "$SHBASE"; branch; printf '# note\n' >> "$ROOT/$p"; _commit "docs: c"
    out="$(floor_out)"; case "$out" in "full "*": $p") ;; *) bad="$bad [$p => '$out']" ;; esac
  done
  [ -z "$bad" ] && pass floor-secret-pattern-beats-first-kind || fail floor-secret-pattern-beats-first-kind "$bad"
}

# A NUL byte means binary: the diff is read from a file, because bash 3.2 drops NULs in a substitution.
case_floor_nul_byte_keeps_the_floor() {
  mkrepo; base src/auth/login.py "$PYBASE"; branch; printf '\000# x\n' >> "$ROOT/src/auth/login.py"; _commit "chore: nul"
  expect floor-nul-byte-keeps-the-floor hit src/auth/login.py
}

# README is a doc; README.sh is code that borrowed the name.
case_floor_readme_exec_is_code() {
  local bad="" out
  mkrepo; branch; put src/auth/README.sh 'echo hi'; _commit "chore: c"; out="$(floor_out)"
  [ "$out" = "full auth: src/auth/README.sh" ] || bad="$bad [README.sh => '$out']"
  mkrepo; branch; put src/auth/README 'notes'; _commit "chore: c"; out="$(floor_out)"
  [ "$out" = "full auth: src/auth/README" ] || bad="$bad [extensionless README => '$out']"
  mkrepo; branch; put src/auth/README.rst 'notes'; put src/auth/README.txt 'notes'; _commit "docs: c"; out="$(floor_out)"
  [ -z "$out" ] || bad="$bad [README.rst, README.txt => '$out']"
  [ -z "$bad" ] && pass floor-readme-exec-is-code || fail floor-readme-exec-is-code "$bad"
}

# Line numbers stay aligned across every blanking: a doc, a test-path exemption, a dropped comment-only file,
# a symlink, then the real hit. A gitlink after the dropped file still reports as a submodule.
case_floor_blanking_keeps_line_numbers_aligned() {
  local bad="" out
  mkrepo; base src/auth/a.py "$PYBASE"; base src/auth/c.py "$PYBASE"; branch
  put docs/auth/x.md x; put tests/auth/login.test.ts x
  printf '# note\n' >> "$ROOT/src/auth/a.py"; ln -s ../../.env "$ROOT/src/auth/b-link.py"; printf 'x = 1\n' >> "$ROOT/src/auth/c.py"
  _commit "fix: mixed"
  out="$(floor_out)"; [ "$out" = "full auth: src/auth/b-link.py" ] || bad="$bad [symlink after dropped file => '$out']"
  mkrepo; base src/auth/a.py "$PYBASE"; branch
  printf '# note\n' >> "$ROOT/src/auth/a.py"
  # `_commit` runs `add -A`, which would stage the gitlink's missing directory as a deletion: stage by hand.
  _git add src/auth/a.py >/dev/null 2>&1; _git update-index --add --cacheinfo "160000,$(_git rev-parse HEAD),zz-sub" >/dev/null 2>&1
  _git commit -q -m "chore: submodule" >/dev/null 2>&1
  out="$(floor_out)"; [ "$out" = "full submodule: zz-sub" ] || bad="$bad [gitlink after dropped file => '$out']"
  [ -z "$bad" ] && pass floor-blanking-keeps-line-numbers-aligned || fail floor-blanking-keeps-line-numbers-aligned "$bad"
}

# The exemption notice on stderr is unchanged by the new drops.
case_floor_exempt_notice_survives_drops() {
  mkrepo
  printf '[gate]\nlane_gates = true\n[[gate.hard_path_exempt]]\npaths = ["scripts/login-*.sh"]\nkinds = ["auth"]\nreason = "smoke script"\n' > "$ROOT/.kit.toml"
  base src/auth/a.py "$PYBASE"; branch
  put scripts/login-smoke.sh 'echo hi'; printf '# note\n' >> "$ROOT/src/auth/a.py"; _commit "chore: c"
  local out err; out="$(floor_out)"; err="$(lcx floor "$ROOT" main 2>&1 >/dev/null)"
  if [ -z "$out" ] && printf '%s' "$err" | grep -q "^floor-exempt.auth.entry 1.scripts/login-\*\.sh.smoke script.*scripts/login-smoke\.sh\$"; then pass floor-exempt-notice-survives-drops
  else fail floor-exempt-notice-survives-drops "stdout='$out' stderr='$err'"; fi
}

case_floor_data_loss_still_hits_in_comments() {
  mkrepo; base app/q.sh "$SHBASE"; branch; printf '# DROP TABLE users;\n' >> "$ROOT/app/q.sh"; _commit "docs: c"
  expect floor-data-loss-still-hits-in-comments hit
}

# ---------------------------------------------------------------------------
# ship_rule_floor: the gate answer, with a stub ledger that always reports unmet gates.
# ---------------------------------------------------------------------------
case_ship_rule_floor_follows_the_diff() {
  local led bad="" rc out
  led="$(_mk)/ledger.sh"; printf '#!/bin/bash\necho "  gap: validate"\nexit 1\n' > "$led"
  # shellcheck disable=SC1090
  source "$SR"
  mkrepo; base src/auth/login.py "$PYBASE"; branch; printf '# note\n' >> "$ROOT/src/auth/login.py"; _commit "docs: comment"
  out="$(KIT_CONFIG_OPERATOR=/nonexistent ship_rule_floor "$ROOT" main HEAD rid-1 "" "$led" 2>&1)"; rc=$?
  [ "$rc" = 0 ] || bad="$bad [comment-only blocked rc=$rc: $out]"
  printf 'x = 1\n' >> "$ROOT/src/auth/login.py"; _commit "fix: code"
  out="$(KIT_CONFIG_OPERATOR=/nonexistent ship_rule_floor "$ROOT" main HEAD rid-1 "" "$led" 2>&1)"; rc=$?
  { [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'hard path (auth: src/auth/login.py)'; } || bad="$bad [code change not blocked rc=$rc: $out]"
  mkrepo; branch; put docs/auth/design.md x; _commit "docs: design"
  out="$(KIT_CONFIG_OPERATOR=/nonexistent ship_rule_floor "$ROOT" main HEAD rid-1 "" "$led" 2>&1)"; rc=$?
  [ "$rc" = 0 ] || bad="$bad [docs blocked rc=$rc: $out]"
  [ -z "$bad" ] && pass ship-rule-floor-follows-the-diff || fail ship-rule-floor-follows-the-diff "$bad"
}

run_case() {
  local fn="case_${1//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; else fail "$1" "no such case"; fi
}
ALL="class-docs-tree-any-extension-is-inert class-code-under-docs-keeps-its-class class-docs-subject-words-ignored class-markdown-anywhere-is-inert class-other-files-keep-class class-docs-plus-code-follows-code check-docs-tree-owes-no-proof floor-docs-never-hit floor-code-under-docs-or-doc-named-still-hits floor-docs-beside-real-hard-path-still-hit floor-comment-only-edit-is-not-a-hit floor-comment-removal-is-not-a-hit floor-code-change-is-a-hit floor-cannot-decide-keeps-the-floor floor-new-comment-only-file-is-not-a-hit floor-skips-comment-only-then-names-the-real-hit floor-cap-keeps-the-floor-on-a-flood floor-hash-that-is-not-a-comment-keeps-the-floor floor-secret-pattern-beats-first-kind floor-nul-byte-keeps-the-floor floor-readme-exec-is-code floor-blanking-keeps-line-numbers-aligned floor-exempt-notice-survives-drops floor-data-loss-still-hits-in-comments ship-rule-floor-follows-the-diff"
if [ "$#" -eq 0 ]; then set -- $ALL; fi
for c in "$@"; do run_case "$c"; done
[ "$FAILS" -eq 0 ]
