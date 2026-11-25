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
SR="${SHIP_RULES_LIB:-$KIT/lib/gate/ship-rules.sh}"

FAILS=0; TMPS=()
_mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS+1)); }

ROOT=""
_git() { git -C "$ROOT" -c commit.gpgsign=false -c core.hooksPath=/dev/null -c core.autocrlf=false "$@"; }
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
  for p in docs/design/uml.html docs/design/sheet.svg docs/img/a.png docs/data/x.csv tools/x/docs/notes.pdf; do
    mkrepo; base docs/README.md base; branch
    put "$p" "$HTML_JS"; _commit "feat: generated drawing set"
    got="$(cls)"; [ "$got" = inert ] || bad="$bad [$p => $got]"
  done
  [ -z "$bad" ] && pass class-docs-tree-any-extension-is-inert || fail class-docs-tree-any-extension-is-inert "$bad"
}

# Source code and secret-shaped files do not become docs by living under docs/.
case_class_code_under_docs_keeps_its_class() {
  local bad="" p got
  for p in docs/design/app.js tools/x/docs/run.sh src/docs/h.py docs/credentials.json docs/secrets/notes.png docs/package.json docs/Makefile docs/docker-compose.yml src/auth/docs/check.json docs/Credentials.JSON; do
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
  for p in docs/auth/design.md docs/design/auth-flow.html docs/auth/flows.csv \
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
  mkrepo; base scripts/login.sh "$SHBASE"; branch; printf '\n' >> "$ROOT/scripts/login.sh"; _commit "style: blank"
  out="$(floor_out)"; [ -z "$out" ] || bad="$bad [blank line after a comment => '$out']"
  # the same blank line right under a shebang touches the lines a shebang depends on: the floor stands
  mkrepo; base scripts/login.sh "$SHBASE"; branch; put scripts/login.sh $'#!/bin/bash\n\nset -e\nrun_migration\n# end'; _commit "style: blank"
  out="$(floor_out)"; [ "$out" = "full auth: scripts/login.sh" ] || bad="$bad [blank under shebang => '$out']"
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
              top-shebang top-coding top-dockerfile del-shift-coding del-shift-dockerfile blank-in-string \
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
      top-shebang)     base src/auth/hook.sh $'#!/bin/bash\necho hi\n# end' ;;
      top-coding)      base src/auth/login.py $'# -*- coding: latin-1 -*-\nx = 1\n# end' ;;
      top-dockerfile)  base Dockerfile $'# syntax=docker/dockerfile:1.4\nFROM alpine\n# end' ;;
      del-shift-coding) base src/auth/login.py $'#!/usr/bin/python\n# author: x\n# -*- coding: latin-1 -*-\nx = 1\n# end' ;;
      del-shift-dockerfile) base Dockerfile $'# syntax=docker/dockerfile:1.4\n# my note\n# escape=`\nFROM alpine\n# end' ;;
      blank-in-string) base src/auth/users.sh $'A="alice\nbob\n\ncarol"\n# end' ;;
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
      top-shebang)     put src/auth/hook.sh $'# note\n#!/bin/bash\necho hi\n# end'; want="full auth: src/auth/hook.sh" ;;
      top-coding)      put src/auth/login.py $'# note one\n# note two\n# -*- coding: latin-1 -*-\nx = 1\n# end'; want="full auth: src/auth/login.py" ;;
      top-dockerfile)  put Dockerfile $'# note\n# syntax=docker/dockerfile:1.4\nFROM alpine\n# end'; want="full infra: Dockerfile" ;;
      del-shift-coding) put src/auth/login.py $'#!/usr/bin/python\n# -*- coding: latin-1 -*-\nx = 1\n# end'; want="full auth: src/auth/login.py" ;;
      del-shift-dockerfile) put Dockerfile $'# syntax=docker/dockerfile:1.4\n# escape=`\nFROM alpine\n# end'; want="full infra: Dockerfile" ;;
      blank-in-string) put src/auth/users.sh $'A="alice\nbob\n\n# eve\ncarol"\n# end'; want="full auth: src/auth/users.sh" ;;
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

# ---------------------------------------------------------------------------
# 3. Added-workflow sizing (Rule A) and the audit line.
#    Fixture: scratch repo with an `origin` remote at the base, one existing workflow whose job name holds a
#    matrix expression, one existing hook, and extra_hard_paths on hooks/ and lib/gate/.
# ---------------------------------------------------------------------------
WF_OK=$'name: lint\non:\n  pull_request:\n    paths:\n      - src/**\npermissions:\n  contents: read\njobs:\n  lint:\n    name: lint check\n    runs-on: self-hosted\n    steps:\n      - name: build\n        run: make lint'
WF_BASE=$'name: ci\non:\n  push:\n    branches:\n      - main\npermissions:\n  contents: read\njobs:\n  build:\n    name: test (${{ matrix.os }})\n    runs-on: self-hosted\n    steps:\n      - run: make test'
HOOKB=$'#!/bin/bash\n\n# guard one\n# guard two\nif [ "$1" = push ]; then exit 2; fi\nexit 0\n# end'
WFP=.github/workflows/new.yml
SHA40=0123456789abcdef0123456789abcdef01234567

# wfrepo [noorigin]: a repo with the fixture committed on main, origin/main at that commit, feat/x checked out.
wfrepo() {
  mkrepo
  printf '[gate]\nlane_gates = true\n\n[lanes]\nextra_hard_paths = "%s"\n' "${WFR_EXTRA:-^hooks/|^lib/gate/}" > "$ROOT/.kit.toml"
  base .github/workflows/ci.yml "${WF_BASE_X:-$WF_BASE}"; base hooks/guard.sh "$HOOKB"
  local f; for f in ${WFR_FILES:-}; do base "$f" "$SHBASE"; done
  branch
  if [ "${1:-}" != noorigin ]; then
    _git remote add origin "$ROOT" >/dev/null 2>&1; _git fetch -q origin >/dev/null 2>&1; _git remote set-head origin main >/dev/null 2>&1
  fi
}
BAD=""
chk() {  # chk <sized|full> <label> <floor output>
  case "$1" in
    sized) [ -z "$3" ] || BAD="$BAD [$2 => '$3']" ;;
    full) case "$3" in "full "*) ;; *) BAD="$BAD [$2 => '$3']" ;; esac ;;
  esac
}
try() {  # try <sized|full> <label> <path> <content>: add one file on top of the fixture
  wfrepo; put "$3" "$4"; _commit "ci: add"; chk "$1" "$2" "$(floor_out)"
}
tryx() {  # tryx <sized|full> <label> <snippet>: any change, run with the repo root as cwd
  wfrepo; ( cd "$ROOT" && eval "$3" ); _commit "ci: change"; chk "$1" "$2" "$(floor_out)"
}
done_case() { [ -z "$BAD" ] && pass "$1" || fail "$1" "$BAD"; BAD=""; }
wf_sub() {  # wf_sub <from> <to>: WF_OK with the first occurrence of <from> replaced (quoted pattern, no & expansion)
  local s="$WF_OK" from="$1" to="$2"
  case "$s" in
    *"$from"*) printf '%s%s%s' "${s%%"$from"*}" "$to" "${s#*"$from"}" ;;
    *) printf '%s' "$s"; echo "wf_sub: pattern not found: $from" >&2 ;;
  esac
}

case_floor_additive_workflow_is_sized() {
  wfrepo; put "$WFP" "$WF_OK"; _commit "ci: add lint"
  local out err; out="$(floor_out)"; err="$(lcx floor "$ROOT" main 2>&1 >/dev/null)"
  [ -z "$out" ] && printf '%s' "$err" | grep -q "^floor-sized	ci	additive-workflow	-	.*	-	$WFP\$" \
    && pass floor-additive-workflow-is-sized || fail floor-additive-workflow-is-sized "out='$out' err='$err'"
}

case_ship_rule_floor_sizes_workflow_add() {
  local led logd out rc
  led="$(_mk)/ledger.sh"; printf '#!/bin/bash\necho "  gap: validate"\nexit 1\n' > "$led"; logd="$(_mk)"
  # shellcheck disable=SC1090
  source "$SR"
  wfrepo; put "$WFP" "$WF_OK"; _commit "ci: add lint"
  out="$(SHIP_RULES_LOG=1 SHIP_RULES_LOG_DIR="$logd" KIT_CONFIG_OPERATOR=/nonexistent ship_rule_floor "$ROOT" main HEAD rid-1 "" "$led" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && grep -q "SIZED | floor | rid-1 (ci: $WFP; additive-workflow)" "$logd/ship-gate.log" \
    && printf '%s' "$out" | grep -q "hard-path sized ci: $WFP" && ! grep -q BLOCKED "$logd/ship-gate.log" 2>/dev/null \
    && pass ship-rule-floor-sizes-workflow-add || fail ship-rule-floor-sizes-workflow-add "rc=$rc out=$out log=$(cat "$logd/ship-gate.log" 2>/dev/null)"
}

case_sized_workflow_still_owes_proof() {
  local bad="" cls1 rc1 rc2 b
  wfrepo; put "$WFP" "$WF_OK"; _commit "ci: add lint"; b="$(_git rev-parse main)"
  [ -z "$(floor_out)" ] || bad="$bad [not sized]"
  cls1="$(env KIT_CONFIG_OPERATOR=/nonexistent bash "$PL" classify "$ROOT" "$b")"
  [ "$cls1" = behavioral ] || bad="$bad [class $cls1]"
  env KIT_CONFIG_OPERATOR=/nonexistent bash "$PL" check "$ROOT" "$b" new >/dev/null 2>&1; rc1=$?
  [ "$rc1" = 1 ] || bad="$bad [no proof, check rc=$rc1]"
  put docs/verification/new.md $'# proof\n\nCommand: bash tests/x.sh\nOutput:\n```\nok 1\n```\nExit: 0\n\nNEGATIVE CONTROL\nCommand: restore, run\nOutput:\n```\nFAIL\n```\nExit: 1\n\nVerdict: PASS'
  _commit "docs: proof"
  env KIT_CONFIG_OPERATOR=/nonexistent bash "$PL" check "$ROOT" "$b" new >/dev/null 2>&1; rc2=$?
  [ "$rc2" = 0 ] || bad="$bad [with proof, check rc=$rc2]"
  [ -z "$bad" ] && pass sized-workflow-still-owes-proof || fail sized-workflow-still-owes-proof "$bad"
}

case_floor_hook_behavior_change_keeps_full() {
  local led out rc
  led="$(_mk)/ledger.sh"; printf '#!/bin/bash\necho "  gap: validate"\nexit 1\n' > "$led"
  # shellcheck disable=SC1090
  source "$SR"
  tryx full hook-behavior "sed -i.bak 's/exit 2/exit 0/' hooks/guard.sh; rm hooks/guard.sh.bak"
  [ "$(floor_out)" = "full extra: hooks/guard.sh" ] || BAD="$BAD [wrong hit '$(floor_out)']"
  out="$(KIT_CONFIG_OPERATOR=/nonexistent ship_rule_floor "$ROOT" main HEAD rid-1 "docs/specs/SPEC-1-x.md" "$led" 2>&1)"; rc=$?
  { [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'hard path (extra: hooks/guard.sh)'; } || BAD="$BAD [ship_rule_floor rc=$rc]"
  done_case floor-hook-behavior-change-keeps-full
}

case_floor_workflow_mixed_diffs_keep_full() {
  WF_OK_X="$WF_OK" tryx full wf-plus-hook "printf '%s\n' \"\$WF_OK_X\" > $WFP; sed -i.bak 's/exit 2/exit 0/' hooks/guard.sh; rm hooks/guard.sh.bak"
  WF_OK_X="$WF_OK" tryx full wf-plus-gate-off "printf '%s\n' \"\$WF_OK_X\" > $WFP; sed -i.bak 's/lane_gates = true/lane_gates = false/' .kit.toml; rm .kit.toml.bak"
  WF_OK_X="$WF_OK" tryx full two-workflows "printf '%s\n' \"\$WF_OK_X\" > $WFP; printf '%s\n' \"\$WF_OK_X\" | sed 's/lint/lint2/g' > .github/workflows/two.yml"
  # a comment-only .github file is dropped before the workflow rule runs; the workflow must still see it
  WF_OK_X="$WF_OK" tryx full wf-plus-comment-only-gh-file "printf '%s\n' \"\$WF_OK_X\" > $WFP; printf '# a\n# b\n' > .github/dependabot.yml"
  WF_OK_X="$WF_OK" tryx full wf-plus-gh-markdown "printf '%s\n' \"\$WF_OK_X\" > $WFP; printf 'notes\n' > .github/NOTES.md"
  done_case floor-workflow-mixed-diffs-keep-full
}

case_floor_workflow_existing_workflow_keeps_full() {
  local mod=$'name: renamed\non:\n  push:\n    branches:\n      - main\npermissions:\n  contents: read\njobs:\n  other:\n    name: other check\n    runs-on: self-hosted\n    steps:\n      - run: make other'
  MOD="$mod" tryx full modified-every-name-changed "printf '%s\n' \"\$MOD\" > .github/workflows/ci.yml"
  MOD="$mod" tryx full renamed-with-new-names "git rm -q .github/workflows/ci.yml; mkdir -p .github/workflows; printf '%s\n' \"\$MOD\" > .github/workflows/moved.yml"
  done_case floor-workflow-existing-workflow-keeps-full
}

case_floor_workflow_escapes_keep_full() {
  try full escape-permission "$WFP" "$(wf_sub '  contents: read' '  contents: "\x77rite"')"
  try full escape-key "$WFP" "$(wf_sub '  contents: read' '  "id-\x74oken": "\x77rite"')"
  try full escape-expression "$WFP" "$(wf_sub 'make lint' '"${{ \x73ecrets.X }}"')"
  # inside a block scalar the grammar admits any text, so only the byte rules stop these
  try full block-backslash "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n          echo \\x77rite')"
  try full block-tab "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n          echo\tx')"
  try full block-cr "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n          echo x\r')"
  try full block-non-ascii "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n          echo caf\xc3\xa9')"
  done_case floor-workflow-escapes-keep-full
}

case_floor_workflow_on_block_tricks_keep_full() {
  try full complex-key "$WFP" "$(wf_sub '  pull_request:' '  ? pull_request_target')"
  try full pr-target "$WFP" "$(wf_sub '  pull_request:' '  pull_request_target:')"
  try full schedule "$WFP" "$(wf_sub '  pull_request:' '  schedule:')"
  try full workflow-run "$WFP" "$(wf_sub '  pull_request:' '  workflow_run:')"
  try full alias-on "$WFP" "$(wf_sub $'on:\n  pull_request:\n    paths:\n      - src/**' 'on: *t')"
  try full flow-on "$WFP" "$(wf_sub $'on:\n  pull_request:\n    paths:\n      - src/**' 'on: {push: null}')"
  try full inline-on "$WFP" "$(wf_sub $'on:\n  pull_request:\n    paths:\n      - src/**' 'on: [push]')"
  try full second-document "$WFP" "$WF_OK"$'\n---\nname: x'
  try full filter-under-dispatch "$WFP" "$(wf_sub '  pull_request:' $'  workflow_dispatch:\n    paths:\n      - a')"
  done_case floor-workflow-on-block-tricks-keep-full
}

case_floor_workflow_name_tricks_keep_full() {
  # base job name: test (${{ matrix.os }}); each new name could satisfy a required check of that name
  try full prefix-of-matrix-name "$WFP" "$(wf_sub 'lint check' 'test')"
  try full job-key-equals-base-key "$WFP" "$(wf_sub '  lint:' '  build:')"
  try full workflow-name-equals-base "$WFP" "$(wf_sub 'name: lint' 'name: ci')"
  try full case-insensitive "$WFP" "$(wf_sub 'lint check' 'CI')"
  try full matrix-shaped "$WFP" "$(wf_sub 'lint check' 'test (ubuntu-latest)')"
  try full reusable-call-shaped "$WFP" "$(wf_sub 'lint check' 'build / test')"
  try full expression-name "$WFP" "$(wf_sub 'lint check' "\${{ 'te' }}st")"
  done_case floor-workflow-name-tricks-keep-full
}

case_floor_workflow_reuse_and_privilege_keep_full() {
  try full job-level-uses "$WFP" "$(wf_sub '    runs-on: self-hosted' $'    uses: ./.github/workflows/release.yml\n    runs-on: self-hosted')"
  try full unpinned-action "$WFP" "$(wf_sub '      - name: build' $'      - uses: actions/checkout@v4\n      - name: build')"
  try full short-pin-action "$WFP" "$(wf_sub '      - name: build' $'      - uses: actions/checkout@'"${SHA40%?}"$'\n      - name: build')"
  try full third-party-action "$WFP" "$(wf_sub '      - name: build' $'      - uses: some/action@'"$SHA40"$'\n      - name: build')"
  try sized pinned-first-party-action "$WFP" "$(wf_sub '      - name: build' $'      - uses: actions/checkout@'"$SHA40"$'\n      - name: build')"
  # a name equal to a target in a base workflow_run list fires that privileged workflow
  wfrepo; _git checkout -q main; put .github/workflows/rel.yml $'name: privileged\non:\n  workflow_run:\n    workflows: [Release Gate]\npermissions:\n  contents: read\njobs:\n  go:\n    runs-on: self-hosted\n    steps:\n      - run: make go'
  _commit "ci: rel"; _git update-ref refs/remotes/origin/main main; _git checkout -q -B feat/x main
  put "$WFP" "$(wf_sub 'name: lint' 'name: Release Gate')"; _commit "ci: add"; chk full workflow-run-target-name "$(floor_out)"
  done_case floor-workflow-reuse-and-privilege-keep-full
}

case_floor_workflow_read_failures_keep_full() {
  try full newline-in-name $'.github/workflows/a\nb.yml' "$WF_OK"
  tryx full empty-file ": > $WFP"
  WF_OK_X="$WF_OK" tryx full nul-byte "{ printf '%s\n' \"\$WF_OK_X\"; printf '# a\\0b\n'; } > $WFP"
  WF_OK_X="$WF_OK" tryx full oversized-file "{ printf '%s\n' \"\$WF_OK_X\"; for i in \$(seq 1 150); do printf '# %0190d\n' \$i; done; } | head -199 > $WFP"
  tryx sized control-valid-file "printf '%s\n' \"\$WF_OK\" > $WFP" 2>/dev/null
  done_case floor-workflow-read-failures-keep-full
}

case_floor_workflow_collision_read_points() {
  local c0 c1 out req=$'name: gate\non:\n  push:\n    branches:\n      - main\npermissions:\n  contents: read\njobs:\n  required:\n    runs-on: self-hosted\n    steps:\n      - run: make gate'
  local new; new="$(wf_sub '  lint:' '  required:')"
  # 1. the branch was cut before the required workflow landed on the default branch: only origin/main sees it
  wfrepo; c0="$(_git rev-parse HEAD)"; _git checkout -q main; put .github/workflows/req.yml "$req"; _commit "ci: req"; c1="$(_git rev-parse HEAD)"
  _git update-ref refs/remotes/origin/main "$c1"; _git checkout -q feat/x; put "$WFP" "$new"; _commit "ci: add"
  out="$(lcx floor "$ROOT" "$c0" 2>/dev/null)"; chk full stale-base-collides-with-origin-tip "$out"
  # 2. KIT_FLOOR_CONFIG_AT names the revision the names are read at (origin tip left at the old base)
  _git update-ref refs/remotes/origin/main "$c0"
  out="$(KIT_FLOOR_CONFIG_AT="$c1" lcx floor "$ROOT" "$c0" 2>/dev/null)"; chk full collision-at-config-rev "$out"
  out="$(lcx floor "$ROOT" "$c0" 2>/dev/null)"; chk sized control-no-collision-anywhere "$out"
  # 3. no origin ref: the default-branch tip cannot be resolved, the floor stands
  wfrepo noorigin; put "$WFP" "$WF_OK"; _commit "ci: add"; chk full no-origin-keeps-floor "$(floor_out)"
  done_case floor-workflow-collision-read-points
}

case_floor_workflow_block_scalar_cannot_smuggle() {
  local r=$'        run: |\n          set -e\n            make lint\n\n          echo done'
  try sized block-with-deeper-and-blank-lines "$WFP" "$(wf_sub '        run: make lint' "$r")"
  # a line inside the block that reads like a key is block text, and stays text
  try sized key-shaped-text-inside-block "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n          make lint\n          env: x\n          if: always()')"
  try full key-after-block-at-step-indent "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n          make lint\n        if: always()')"
  try full job-key-after-block "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n          make lint\n    permissions:\n      contents: write')"
  try full first-line-deeper-than-ten "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n            make lint\n          env: x')"
  try full block-chomp-indicator "$WFP" "$(wf_sub '        run: make lint' $'        run: |-\n          make lint')"
  try full folded-scalar "$WFP" "$(wf_sub '        run: make lint' $'        run: >\n          make lint')"
  try full empty-block "$WFP" "$(wf_sub '        run: make lint' $'        run: |\n      - run: make x')"
  try full block-ends-at-eof-empty "$WFP" "$(wf_sub '        run: make lint' '        run: |')"
  done_case floor-workflow-block-scalar-cannot-smuggle
}

case_floor_workflow_odd_path_keeps_full() {
  local p
  for p in .github/workflows/sub/x.yml .github/workflows/x.yml.off .github/workflows/login.yml .github/workflows/x_y+z.yml \
           .github/actions/a/action.yml .github/CODEOWNERS .github/dependabot.yml .github/x.json .github/workflows/x.sh; do
    try full "path $p" "$p" "$WF_OK"
  done
  try sized control-yaml-extension .github/workflows/ok.yaml "$WF_OK"
  done_case floor-workflow-odd-path-keeps-full
}

case_floor_workflow_odd_file_keeps_full() {
  WF_OK_X="$WF_OK" tryx full symlink "ln -s ../../README.md $WFP"
  WF_OK_X="$WF_OK" tryx full executable-mode "printf '%s\n' \"\$WF_OK_X\" > $WFP; chmod +x $WFP"
  WF_OK_X="$WF_OK" tryx full cr-byte "printf '%s\r\n' \"\$WF_OK_X\" > $WFP"
  WF_OK_X="$WF_OK" tryx full tab-byte "printf '%s\n# a\tb\n' \"\$WF_OK_X\" > $WFP"
  WF_OK_X="$WF_OK" tryx full non-ascii "printf '%s\n# caf\303\251\n' \"\$WF_OK_X\" > $WFP"
  WF_OK_X="$WF_OK" tryx full trailing-space "printf '%s \n' \"\$WF_OK_X\" > $WFP"
  WF_OK_X="$WF_OK" tryx full over-200-lines "{ printf '%s\n' \"\$WF_OK_X\"; for i in \$(seq 1 200); do printf '# c\n'; done; } > $WFP"
  done_case floor-workflow-odd-file-keeps-full
}

case_floor_workflow_grammar_refusals() {
  local x
  try full if-key "$WFP" "$(wf_sub '        run: make lint' $'        if: always()\n        run: make lint')"
  try full step-env "$WFP" "$(wf_sub '        run: make lint' $'        env:\n          A: b\n        run: make lint')"
  try full job-needs "$WFP" "$(wf_sub '    runs-on: self-hosted' $'    needs: other\n    runs-on: self-hosted')"
  try full job-strategy "$WFP" "$(wf_sub '    runs-on: self-hosted' $'    strategy:\n      matrix:\n        os: [a]\n    runs-on: self-hosted')"
  try full continue-on-error "$WFP" "$(wf_sub '    runs-on: self-hosted' $'    continue-on-error: true\n    runs-on: self-hosted')"
  try full job-permissions "$WFP" "$(wf_sub '    runs-on: self-hosted' $'    permissions:\n      contents: write\n    runs-on: self-hosted')"
  try full write-all "$WFP" "$(wf_sub $'permissions:\n  contents: read' 'permissions: write-all')"
  try full contents-write "$WFP" "$(wf_sub '  contents: read' '  contents: write')"
  try full extra-permission "$WFP" "$(wf_sub '  contents: read' $'  contents: read\n  issues: read')"
  try full no-permissions "$WFP" "$(wf_sub $'permissions:\n  contents: read\n' '')"
  try sized permissions-empty-braces "$WFP" "$(wf_sub $'permissions:\n  contents: read' 'permissions: {}')"
  try full other-brace "$WFP" "$(wf_sub $'permissions:\n  contents: read' 'permissions: {contents: write}')"
  try full secrets-in-run "$WFP" "$(wf_sub 'make lint' 'make lint ${{ secrets.X }}')"
  try full anchor "$WFP" "$(wf_sub 'name: lint check' 'name: &a lint check')"
  try full tag "$WFP" "$(wf_sub 'make lint' '!!str make lint')"
  try full merge-key "$WFP" "$(wf_sub '    runs-on: self-hosted' $'    <<: *a\n    runs-on: self-hosted')"
  try full percent-directive "$WFP" $'%YAML 1.2\n'"$WF_OK"
  try full run-colon "$WFP" "$(wf_sub 'make lint' 'make lint: now')"
  try full run-comment "$WFP" "$(wf_sub 'make lint' 'make lint # x')"
  try full run-flow "$WFP" "$(wf_sub 'make lint' '[make, lint]')"
  try full run-and-uses "$WFP" "$(wf_sub '        run: make lint' $'        uses: actions/checkout@'"$SHA40"$'\n        run: make lint')"
  try full duplicate-run "$WFP" "$(wf_sub '        run: make lint' $'        run: make lint\n        run: make other')"
  try full duplicate-name "$WFP" "$(wf_sub 'name: lint' $'name: lint\nname: other')"
  try full runs-on-flow-other "$WFP" "$(wf_sub 'self-hosted' '[ubuntu-latest]')"
  try sized runs-on-self-hosted-labels "$WFP" "$(wf_sub 'runs-on: self-hosted' 'runs-on: [self-hosted, macOS, ARM64]')"
  try full boolean-name "$WFP" "$(wf_sub 'lint check' 'yes')"
  try full job-without-steps "$WFP" "$(wf_sub $'    steps:\n      - name: build\n        run: make lint' '    timeout-minutes: 5')"
  try full quoted-list-item "$WFP" "$(wf_sub $'  pull_request:\n    paths:\n      - src/**' $'  push:\n    branches:\n      - "main"')"
  try full odd-indent "$WFP" "$(wf_sub '    name: lint check' '   name: lint check')"
  done_case floor-workflow-grammar-refusals
}

case_floor_workflow_data_loss_line_keeps_full() {
  local out
  wfrepo; put "$WFP" "$(wf_sub 'make lint' 'psql -c "drop table users"')"; _commit "ci: add"; out="$(floor_out)"
  [ "$out" = "full data-loss: $WFP" ] && pass floor-workflow-data-loss-line-keeps-full || fail floor-workflow-data-loss-line-keeps-full "got '$out'"
}

case_floor_code_to_comment_keeps_full() {
  tryx full code-turned-comment "sed -i.bak 's/^if \\[/# if [/' hooks/guard.sh; rm hooks/guard.sh.bak"
  tryx full json-under-github "printf '{\"a\": 1}\n' > .github/settings.json"
  tryx full kittoml-comment-below-code "printf '# note\n' >> .kit.toml"
  tryx sized control-comment-after-comment "sed -i.bak 's/# guard two/# guard two edited/' hooks/guard.sh; rm hooks/guard.sh.bak"
  done_case floor-code-to-comment-keeps-full
}

case_floor_comment_edit_is_sized_and_logged() {
  local out err
  wfrepo; ( cd "$ROOT" && sed -i.bak 's/# guard two/# guard two edited/' hooks/guard.sh; rm hooks/guard.sh.bak ); _commit "docs: comment"
  out="$(floor_out)"; err="$(lcx floor "$ROOT" main 2>&1 >/dev/null)"
  [ -z "$out" ] && printf '%s' "$err" | grep -q "^floor-sized	extra	comment-only	-	.*	-	hooks/guard.sh\$" \
    && pass floor-comment-edit-is-sized-and-logged || fail floor-comment-edit-is-sized-and-logged "out='$out' err='$err'"
}

case_floor_config_key_flip_keeps_full() {
  tryx full flip-neutral-key "printf '[mega]\nwave_cap = 3\n' >> .kit.toml"
  tryx full flip-gate-key "sed -i.bak 's/lane_gates = true/lane_gates = false/' .kit.toml; rm .kit.toml.bak"
  done_case floor-config-key-flip-keeps-full
}

case_sized_notices_relay_and_cap() {
  local lines i out bad=""
  # 25 comment-only drops come first, then the workflow drop: the workflow line must survive the cap
  lines=""
  for i in $(seq 1 25); do lines="${lines}floor-sized	extra	comment-only	-	r	-	.a$i/Dockerfile"$'\n'; done
  lines="${lines}floor-sized	ci	additive-workflow	-	r	-	$WFP"$'\n'
  # shellcheck disable=SC1090
  source "$SR"
  out="$(printf '%s' "$lines" | _sr_relay rid-1)"
  printf '%s\n' "$out" | grep -q "^L	SIZED | floor | rid-1 (ci: $WFP; additive-workflow)" || bad="$bad [workflow SIZED log line lost]"
  [ "$(printf '%s\n' "$out" | grep -c '^L	SIZED | floor | rid-1 (extra: .a')" = 20 ] || bad="$bad [comment log lines not capped at 20]"
  printf '%s\n' "$out" | grep -q '^L	SIZED | floor | rid-1 (comment-only: 5 more files)' || bad="$bad [no L count line]"
  printf '%s\n' "$out" | grep -q '^A	\[advisory\] hard-path sized: 5 more comment-only files' || bad="$bad [no A count line]"
  printf '%s\n' "$out" | grep -q "^A	\[advisory\] hard-path sized ci: $WFP (additive-workflow)" || bad="$bad [workflow advisory lost]"
  out="$(printf 'floor-sized\tci\tadditive-workflow\t-\tr\t-\t.github/workflows/a|b\xc3\xa9.yml\n' | _sr_relay rid-1)"
  printf '%s\n' "$out" | grep -q 'workflows/a?b??.yml' || bad="$bad [odd bytes not folded: $out]"
  [ -z "$bad" ] && pass sized-notices-relay-and-cap || fail sized-notices-relay-and-cap "$bad"
}

case_floor_sized_flood_keeps_floor() {
  local i out files=""
  for i in $(seq 1 51); do files="$files db/migrations/m$i.sh"; done
  WFR_FILES="$files" wfrepo
  for i in $(seq 1 51); do printf '# note\n' >> "$ROOT/db/migrations/m$i.sh"; done; put "$WFP" "$WF_OK"; _commit "docs: comments and workflow"
  out="$(floor_out)"
  case "$out" in "full "*) pass floor-sized-flood-keeps-floor ;; *) fail floor-sized-flood-keeps-floor "got '$out'" ;; esac
}


# --- Review round: the base side is "anything we cannot classify keeps the floor".
# A base workflow whose name holds an expression becomes a glob; every other base shape is classified or refused.
basetry() {  # basetry <sized|full> <label> <base ci.yml text> [<new workflow text>]
  WF_BASE_X="$3" try "$1" "$2" "$WFP" "${4:-$WF_OK}"
}
wf_base_sub() {  # wf_base_sub <from> <to>: WF_BASE with the first occurrence replaced
  local s="$WF_BASE" from="$1" to="$2"
  case "$s" in *"$from"*) printf '%s%s%s' "${s%%"$from"*}" "$to" "${s#*"$from"}" ;; *) printf '%s' "$s"; echo "wf_base_sub: not found: $from" >&2 ;; esac
}

case_floor_workflow_base_expression_names() {
  local nm='    name: test (${{ matrix.os }})' nw
  basetry full expression-suffix "$(wf_base_sub "$nm" '    name: lint-${{ matrix.lang }}')" "$(wf_sub '  lint:' '  lint-go:')"
  basetry full expression-suffix-job-name "$(wf_base_sub "$nm" '    name: lint-${{ matrix.lang }}')" "$(wf_sub 'lint check' 'lint-py')"
  basetry full matrix-include-bare-expression "$(wf_base_sub "$nm" '    name: ${{ matrix.target }}')" "$(wf_sub '  lint:' '  linux-e2e:')"
  basetry full bare-expression-matches-any-name "$(wf_base_sub "$nm" '    name: ${{ matrix.target }}')"
  basetry full expression-in-middle "$(wf_base_sub "$nm" '    name: a-${{ matrix.x }}-z')" "$(wf_sub 'lint check' 'a-q-z')"
  basetry full unterminated-expression "$(wf_base_sub "$nm" '    name: a-${{ matrix.x')"
  basetry sized glob-does-not-match-other-name "$(wf_base_sub "$nm" '    name: unit-${{ matrix.x }}')"
  basetry sized glob-suffix-mismatch "$(wf_base_sub "$nm" '    name: ${{ matrix.x }}-unit')"
  done_case floor-workflow-base-expression-names
}

case_floor_workflow_base_workflow_run_anywhere() {
  local wr=$'name: privileged\non:\n  workflow_run:\n    workflows: [Release Gate]\npermissions:\n  contents: read\njobs:\n  go:\n    runs-on: self-hosted\n    steps:\n      - run: make go'
  basetry full workflow-run-one-line-list "$wr"
  basetry full workflow-run-multi-line-list "${wr/\[Release Gate\]/[
      \"Release Gate\"
    ]}"
  basetry full workflow-run-scalar "${wr/\[Release Gate\]/Release Gate}"
  basetry full workflow-run-unrelated-new-name "$wr" "$WF_OK"
  basetry full workflow-run-in-a-comment "${WF_BASE}"$'\n# triggered by workflow_run elsewhere'
  basetry full workflow-run-upper-case "${wr/workflow_run/Workflow_Run}"
  basetry sized control-no-workflow-run "$WF_BASE"
  done_case floor-workflow-base-workflow-run-anywhere
}

case_floor_workflow_base_unclassifiable_keeps_full() {
  local j='  build:'
  basetry full quoted-job-key "$(wf_base_sub "$j" '  "required":')"
  basetry full single-quoted-job-key "$(wf_base_sub "$j" "  'required':")"
  basetry full folded-name "$(wf_base_sub '    name: test (${{ matrix.os }})' $'    name: >-\n      Required Check')"
  basetry full literal-name "$(wf_base_sub '    name: test (${{ matrix.os }})' $'    name: |\n      Required Check')"
  basetry full empty-name "$(wf_base_sub '    name: test (${{ matrix.os }})' '    name:')"
  basetry full anchored-name "$(wf_base_sub '    name: test (${{ matrix.os }})' '    name: &n Required')"
  basetry full alias-name "$(wf_base_sub '    name: test (${{ matrix.os }})' '    name: *n')"
  basetry full flow-job-map "$(wf_base_sub "$j" '  build: {runs-on: self-hosted, name: Required}')"
  basetry full anchored-job "$(wf_base_sub "$j" '  build: &b')"
  basetry full inline-jobs $'name: ci\non:\n  push:\npermissions:\n  contents: read\njobs: {required: {runs-on: x}}'
  basetry full job-key-with-dot "$(wf_base_sub "$j" '  build.x:')"
  basetry full job-level-uses "$(wf_base_sub '    runs-on: self-hosted' '    uses: ./.github/workflows/call.yml')"
  basetry full complex-key "$(wf_base_sub '    runs-on: self-hosted' $'    ? required\n    runs-on: self-hosted')"
  basetry full merge-key "$(wf_base_sub '    runs-on: self-hosted' $'    <<: *x\n    runs-on: self-hosted')"
  basetry full tab-in-base "$(wf_base_sub '    runs-on: self-hosted' $'\truns-on: self-hosted')"
  basetry full document-marker "$WF_BASE"$'\n---\nname: x'
  basetry full flow-document $'{"name": "ci", "jobs": {"b": {}}}'
  basetry full quoted-workflow-name-with-escape $'name: "a\\x41"\non:\n  push:\npermissions:\n  contents: read\njobs:\n  build:\n    runs-on: self-hosted\n    steps:\n      - run: make'
  basetry full unclassified-top-level $'name: ci\n- x\njobs:\n  build:\n    runs-on: self-hosted'
  basetry sized control-quoted-plain-name "$(wf_base_sub '    name: test (${{ matrix.os }})' '    name: "Unit"')"
  done_case floor-workflow-base-unclassifiable-keeps-full
}

case_floor_workflow_replaced_objects_keep_full() {
  local evil benign out
  wfrepo
  put "$WFP" $'name: lint\non:\n  pull_request:\npermissions:\n  contents: write\njobs:\n  lint:\n    runs-on: self-hosted\n    steps:\n      - run: make lint'
  _commit "ci: add"
  evil="$(_git rev-parse HEAD:"$WFP")"; benign="$(printf '%s\n' "$WF_OK" | _git hash-object -w --stdin)"
  _git replace "$evil" "$benign" >/dev/null 2>&1
  out="$(floor_out)"; chk full replaced-blob-hides-write-permission "$out"
  _git replace -d "$evil" >/dev/null 2>&1
  try sized control-no-replace "$WFP" "$WF_OK"
  done_case floor-workflow-replaced-objects-keep-full
}

case_floor_workflow_byte_count_must_be_digits() {
  local d; d="$(_mk)"; printf '#!/bin/sh\necho x\n' > "$d/wc"; chmod +x "$d/wc"
  wfrepo; put "$WFP" "$WF_OK"; _commit "ci: add"
  chk full wc-prints-garbage "$(PATH="$d:$PATH" floor_out)"
  printf '#!/bin/sh\necho\n' > "$d/wc"
  chk full wc-prints-nothing "$(PATH="$d:$PATH" floor_out)"
  chk sized control-real-wc "$(floor_out)"
  done_case floor-workflow-byte-count-must-be-digits
}

case_floor_tools_missing_prints_a_hit() {
  local d t out bash_bin n tools="git awk sed tr grep wc head cut cmp mktemp cp mv rm cat sort paste basename "
  bash_bin="$(command -v bash)"
  tools="$tools"env   # every external command the floor verb's code path runs, read from its functions
  for t in $tools; do
    d="$(_mk)"
    for n in $tools dirname tail date mkdir readlink uname id sleep; do
      [ "$n" != "$t" ] || continue
      [ ! -x "$(command -v "$n" 2>/dev/null)" ] || ln -s "$(command -v "$n")" "$d/$n"
    done
    wfrepo; put "$WFP" "$WF_OK"; _commit "ci: add"
    out="$(P="$d" "$bash_bin" -c 'exec env -i HOME="$HOME" PATH="$P" KIT_CONFIG_OPERATOR=/nonexistent "$0" "$@"' "$bash_bin" "$LC" floor "$ROOT" main 2>/dev/null)"
    [ "$out" = "full tools-missing: $t" ] || BAD="$BAD [without $t => '$out']"
  done
  wfrepo; put "$WFP" "$WF_OK"; _commit "ci: add"
  out="$(TMPDIR=/nonexistent/dir lcx floor "$ROOT" main 2>/dev/null)"
  [ "$out" = "full tools-missing: tmpdir" ] || BAD="$BAD [no temp dir => '$out']"
  done_case floor-tools-missing-prints-a-hit
}

case_floor_workflow_action_allowlist() {
  local sha="$SHA40" a
  for a in cache upload-artifact github-script download-artifact; do
    try full "actions/$a" "$WFP" "$(wf_sub '      - name: build' $'      - uses: actions/'"$a"$'@'"$sha"$'\n      - name: build')"
  done
  try full third-party "$WFP" "$(wf_sub '      - name: build' $'      - uses: docker/login-action@'"$sha"$'\n      - name: build')"
  try sized actions-checkout "$WFP" "$(wf_sub '      - name: build' $'      - uses: actions/checkout@'"$sha"$'\n      - name: build')"
  try sized actions-setup-node "$WFP" "$(wf_sub '      - name: build' $'      - uses: actions/setup-node@'"$sha"$'\n      - name: build')"
  done_case floor-workflow-action-allowlist
}

# Each fixture below is the one valid sized workflow with exactly one thing changed, so only its own check refuses it.
case_floor_workflow_single_fault_rows() {
  try full quoted-permission-value "$WFP" "$(wf_sub '  contents: read' '  contents: "read"')"
  try full quoted-permission-key "$WFP" "$(wf_sub '  contents: read' '  "contents": read')"
  try full expression-in-a-comment "$WFP" "$WF_OK"$'\n# ${{ github.sha }}'
  try full unpinned-checkout "$WFP" "$(wf_sub '      - name: build' $'      - uses: actions/checkout@v4\n      - name: build')"
  try full third-party-action "$WFP" "$(wf_sub '      - name: build' $'      - uses: some/action@'"$SHA40"$'\n      - name: build')"
  tryx full empty-file ": > $WFP"
  WF_OK_X="$WF_OK" tryx full executable-mode "printf '%s\n' \"\$WF_OK_X\" > $WFP; chmod +x $WFP"
  try full second-document-marker "$WFP" "$WF_OK"$'\n---'
  WFR_EXTRA='^hooks/|^\.github/workflows/ex-' try full extra-hard-path-also-matches ".github/workflows/ex-a.yml" "$WF_OK"
  try sized control-one-valid-file "$WFP" "$WF_OK"
  done_case floor-workflow-single-fault-rows
}


case_floor_workflow_base_name_continues() {
  local nm='    name: test (${{ matrix.os }})'
  basetry full job-name-plain-continues "$(wf_base_sub "$nm" $'    name: Required\n      Check')" "$(wf_sub 'lint check' 'Required Check')"
  basetry full job-name-continues-with-expression "$(wf_base_sub "$nm" $'    name: Lint\n      ${{ matrix.v }}')" "$(wf_sub 'lint check' 'Lint go' | sed 's/^  lint:/  other:/')"
  basetry full job-name-continues-unrelated-new-name "$(wf_base_sub "$nm" $'    name: Required\n      Check')"
  basetry full workflow-name-continues "$(printf '%s' "$WF_BASE" | sed '1s/.*/name: Required\n  Check/')" "$(wf_sub 'name: lint' 'name: Required Check')"
  basetry full continuation-after-a-comment-line "$(wf_base_sub "$nm" $'    name: Required\n    # note\n      Check')"
  basetry full continuation-after-a-blank-line "$(wf_base_sub "$nm" $'    name: Required\n\n      Check')"
  basetry sized control-next-key-same-indent "$(wf_base_sub "$nm" $'    name: Required')"
  basetry sized control-comment-then-same-indent-key "$(wf_base_sub "$nm" $'    name: Required\n      # deeper comment\n    # same-level comment')"
  done_case floor-workflow-base-name-continues
}

case_floor_workflow_base_glob_braces() {
  local nm='    name: test (${{ matrix.os }})'
  basetry full brace-inside-an-expression-string "$(wf_base_sub "$nm" "    name: \${{ '}}' && 'Required' }}")" "$(wf_sub 'lint check' 'Required')"
  basetry full stray-closing-braces "$(wf_base_sub "$nm" '    name: lint-}}')" "$(wf_sub 'lint check' 'lint-x')"
  basetry full nested-opening "$(wf_base_sub "$nm" '    name: a-${{ ${{ x }} }}')"
  basetry sized control-plain-expression "$(wf_base_sub "$nm" '    name: unit-${{ matrix.x }}')"
  done_case floor-workflow-base-glob-braces
}


case_floor_workflow_base_byte_rule() {
  local rn='    runs-on: self-hosted' nel=$'\xc2\x85'
  basetry full bare-cr-hides-a-name "$(wf_base_sub "$rn" $'    timeout-minutes: 5\r    name: Required')" "$(wf_sub 'lint check' 'Required')"
  basetry full nel-hides-a-name "$(wf_base_sub "$rn" "    timeout-minutes: 5${nel}    name: Required")" "$(wf_sub 'lint check' 'Required')"
  basetry full tab-in-a-comment "${WF_BASE}"$'\n# a\tb'
  basetry full utf8-letter-in-a-comment "${WF_BASE}"$'\n# caf\xc3\xa9'
  basetry full byte-order-mark $'\xef\xbb\xbf'"$WF_BASE"
  basetry full bare-cr-inside-a-comment "${WF_BASE}"$'\n# note\rmore'
  basetry sized crlf-file-still-classifies "${WF_BASE//$'\n'/$'\r\n'}"
  basetry sized control-plain-ascii "$WF_BASE"
  done_case floor-workflow-base-byte-rule
}

# Each finding's checks carry a `# chk:<id>` tag. A copy of the libs with one id switched off (bad( becomes a
# no-op, `return 1` becomes `true`) must turn that finding's rows RED; the real libs keep them green.
mut_libs() {  # mut_libs <id> <extra-sed-expr-lane-classify|-> <extra-sed-expr-ship-rules|->; prints the copy dir
  local d id="$1" re
  d="$(_mk)"; cp -R "$KIT/lib" "$d/lib"; cp "$KIT/kit.toml" "$d/kit.toml" 2>/dev/null
  re="# chk:([A-Za-z0-9]+ )*$id( [A-Za-z0-9]+)*\$"
  sed -E -e "/$re/s/(bad|unsafe)\\(/ign(/g" -e "/$re/s/return 1/true/g" "$KIT/lib/classify/lane-classify.sh" > "$d/lib/classify/lane-classify.sh"
  [ "${2:--}" = - ] || { sed -E -e "$2" "$d/lib/classify/lane-classify.sh" > "$d/lc.tmp" && mv "$d/lc.tmp" "$d/lib/classify/lane-classify.sh"; }
  [ "${3:--}" = - ] || { sed -E -e "$3" "$KIT/lib/gate/ship-rules.sh" > "$d/lib/gate/ship-rules.sh"; }
  printf '%s' "$d"
}
mut_red() {  # mut_red <id> <label> <lc-sed|-> <sr-sed|-> <case>...: the cases must report FAIL on the mutated libs
  local id="$1" label="$2" lcs="$3" srs="$4" d out; shift 4
  d="$(mut_libs "$id" "$lcs" "$srs")"
  if cmp -s "$d/lib/classify/lane-classify.sh" "$KIT/lib/classify/lane-classify.sh" && cmp -s "$d/lib/gate/ship-rules.sh" "$KIT/lib/gate/ship-rules.sh"; then
    BAD="$BAD [$label: the mutation changed nothing]"; return
  fi
  out="$(LANE_CLASSIFY_LIB="$d/lib/classify/lane-classify.sh" SHIP_RULES_LIB="$d/lib/gate/ship-rules.sh" bash "$KIT/tests/test-ceremony-fits-diff.sh" "$@" 2>&1)"
  [ -z "${MUT_SHOW:-}" ] || printf 'MUT %s: %s\n' "$id" "$(printf '%s\n' "$out" | grep '^FAIL ' | cut -c1-260)"
  printf '%s\n' "$out" | grep '^FAIL ' | grep -q -- "${WANT:-}" || BAD="$BAD [$label: rows stayed green with the checks off]"
}
case_rule_a_checks_are_load_bearing() {
  mut_red ALL "whole Rule A drop" 's/if \[ "\$bestkind" = ci \] && _floor_workflow_additive/if false \&\& _floor_workflow_additive/' - \
    floor-additive-workflow-is-sized ship-rule-floor-sizes-workflow-add
  mut_red G "grammar" - - floor-workflow-grammar-refusals floor-workflow-on-block-tricks-keep-full floor-workflow-reuse-and-privilege-keep-full
  mut_red F1 "finding 1 byte rules" - - floor-workflow-escapes-keep-full
  mut_red F2 "finding 2 on-block grammar" - - floor-workflow-on-block-tricks-keep-full
  mut_red F3 "finding 3 names" - - floor-workflow-name-tricks-keep-full
  mut_red F4 "finding 4 reuse" - - floor-workflow-reuse-and-privilege-keep-full
  mut_red F5 "finding 5 read" - - floor-workflow-read-failures-keep-full floor-workflow-odd-path-keeps-full
  mut_red F6 "finding 6 uncapped workflow line" - 's/rule != "comment-only" \|\| \+\+nz <= 20/++nz <= 20/' sized-notices-relay-and-cap
  mut_red F7 "finding 7 read points" 's/for rev in "\$base" "\$\{KIT_FLOOR_CONFIG_AT:-\}" "\$def"; do/for rev in "$base"; do/' - floor-workflow-collision-read-points
  mut_red F9 "finding 9 unblanked list" - - floor-workflow-mixed-diffs-keep-full
  mut_red F10 "finding 10 status" - - floor-workflow-existing-workflow-keeps-full
  mut_red BLK "block scalar tracking" 's/RLENGTH >= 10 && \(blkn/RLENGTH >= 14 \&\& (blkn/' - floor-workflow-block-scalar-cannot-smuggle
  mut_red NOTE "audit line" 's/^_floor_sized_note\(\) \{/_floor_sized_note() { return 0;/' - floor-additive-workflow-is-sized floor-comment-edit-is-sized-and-logged
  mut_red R1 "review 1 expression glob" 's/o = o substr\(v, 1, i - 1\) "\*"/o = o substr(v, 1, i - 1) "~"/' - floor-workflow-base-expression-names
  mut_red R2 "review 2 workflow_run anywhere" - - floor-workflow-base-workflow-run-anywhere
  mut_red R3 "review 3 unclassifiable base" - - floor-workflow-base-unclassifiable-keeps-full
  mut_red R4 "review 4 replace objects" 's/git --no-replace-objects/git/; s/export GIT_NO_REPLACE_OBJECTS=1/:/' - floor-workflow-replaced-objects-keep-full
  mut_red R5 "review 5 digits" - - floor-workflow-byte-count-must-be-digits
  mut_red R6 "review 6 tools" 's/_floor_tools_ok \|\| return 0/true/' - floor-tools-missing-prints-a-hit
  mut_red R7 "review 7 action allowlist" 's/\(checkout\|setup-/(checkout|cache|upload-artifact|github-script|download-artifact|setup-/' - floor-workflow-action-allowlist
  mut_red R8 "round 2 row 1 name continuation" - - floor-workflow-base-name-continues
  mut_red R9 "round 2 row 2 glob braces" - - floor-workflow-base-glob-braces
  mut_red R10 "round 3 base byte rule" - - floor-workflow-base-byte-rule
  WANT=quoted-permission-value mut_red PERM "single fault: permission" - - floor-workflow-single-fault-rows
  WANT=quoted-permission-key mut_red PERM "single fault: permission key" - - floor-workflow-single-fault-rows
  WANT=unpinned-checkout mut_red PIN "single fault: unpinned" - - floor-workflow-single-fault-rows
  WANT=third-party-action mut_red PIN "single fault: third party" - - floor-workflow-single-fault-rows
  WANT=empty-file mut_red EMPTY "single fault: empty" - - floor-workflow-single-fault-rows
  WANT=executable-mode mut_red MODE "single fault: mode" - - floor-workflow-single-fault-rows
  WANT=expression-in-a-comment mut_red F3 "single fault: expression" - - floor-workflow-single-fault-rows
  WANT=second-document-marker mut_red F2 "single fault: document" - - floor-workflow-single-fault-rows
  WANT=extra-hard-path-also-matches mut_red EXTRA "single fault: extra path" - - floor-workflow-single-fault-rows
  done_case rule-a-checks-are-load-bearing
}

run_case() {
  local fn="case_${1//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; else fail "$1" "no such case"; fi
}
ALL="class-docs-tree-any-extension-is-inert class-code-under-docs-keeps-its-class class-docs-subject-words-ignored class-markdown-anywhere-is-inert class-other-files-keep-class class-docs-plus-code-follows-code check-docs-tree-owes-no-proof floor-docs-never-hit floor-code-under-docs-or-doc-named-still-hits floor-docs-beside-real-hard-path-still-hit floor-comment-only-edit-is-not-a-hit floor-comment-removal-is-not-a-hit floor-code-change-is-a-hit floor-cannot-decide-keeps-the-floor floor-new-comment-only-file-is-not-a-hit floor-skips-comment-only-then-names-the-real-hit floor-cap-keeps-the-floor-on-a-flood floor-hash-that-is-not-a-comment-keeps-the-floor floor-secret-pattern-beats-first-kind floor-nul-byte-keeps-the-floor floor-readme-exec-is-code floor-blanking-keeps-line-numbers-aligned floor-exempt-notice-survives-drops floor-data-loss-still-hits-in-comments ship-rule-floor-follows-the-diff floor-additive-workflow-is-sized ship-rule-floor-sizes-workflow-add sized-workflow-still-owes-proof floor-hook-behavior-change-keeps-full floor-workflow-mixed-diffs-keep-full floor-workflow-existing-workflow-keeps-full floor-workflow-escapes-keep-full floor-workflow-on-block-tricks-keep-full floor-workflow-name-tricks-keep-full floor-workflow-reuse-and-privilege-keep-full floor-workflow-read-failures-keep-full floor-workflow-collision-read-points floor-workflow-block-scalar-cannot-smuggle floor-workflow-odd-path-keeps-full floor-workflow-odd-file-keeps-full floor-workflow-grammar-refusals floor-workflow-data-loss-line-keeps-full floor-code-to-comment-keeps-full floor-comment-edit-is-sized-and-logged floor-config-key-flip-keeps-full sized-notices-relay-and-cap floor-sized-flood-keeps-floor floor-workflow-base-expression-names floor-workflow-base-workflow-run-anywhere floor-workflow-base-unclassifiable-keeps-full floor-workflow-replaced-objects-keep-full floor-workflow-byte-count-must-be-digits floor-tools-missing-prints-a-hit floor-workflow-action-allowlist floor-workflow-single-fault-rows floor-workflow-base-name-continues floor-workflow-base-glob-braces floor-workflow-base-byte-rule rule-a-checks-are-load-bearing"
if [ "$#" -eq 0 ]; then set -- $ALL; fi
for c in "$@"; do run_case "$c"; done
[ "$FAILS" -eq 0 ]
