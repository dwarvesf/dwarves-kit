#!/usr/bin/env bash
# boundary-lint.sh -- the engine never names a consumer, by path or by
# skill (learning-boundary), its code never carries the operator's identity, and its runtime
# data paths live in one resolver. Four checks, all read-only.
#
# PATH: all of lib/ and hooks/ (minus four modules named below), commands/, tests/, kit.toml
# for a hardcoded dotfiles or ops-toolkit path -- the shape behind the PR #554 regression (a
# kit test reached into the operator's dotfiles by absolute path); tests/test-weekend-batch.sh
# already pins the same `dotfiles/home` pattern as its own precedent. Excluded:
# lib/{plugin-check,webcheck,sync,stats}/ -- each carries real, unrelated "graduated/migrated
# from ops-toolkit/tools/X" provenance prose in its own README/SPEC/docs (verified: measured
# 20+ such hits, zero of them a live path any code reads), which this lint has no mandate to
# rewrite. A hit in any OTHER module is real; see the engine-learn-seam spec for the
# full rationale and why a wider net there would break green on introduction.
#
# NAME: an explicit, small file list (the seam-adjacent surfaces this repo owns) for a
# hardcoded consumer-skill name that should route through a config seam instead. NOT a
# directory-wide scan: `narrate-log`/`deep-understand`/etc. have real, unrelated, legitimate
# hits elsewhere (commands/pitch.md composes narrate-log for an unrelated feature;
# tests/test-wrap.sh uses "learning-ledger" as generic fixture text). See
# the engine-learn-seam spec.
#
# DENY: executable code and fixtures never carry the operator's identity. The tokens in
# deny_re (the operator's workers.dev host, GitHub handle, personal monorepo, vault name) are
# the shape of a default that belonged in the operator's kit.toml (lib/config/kit-config.sh,
# kit_config_get_root) instead of the code. Scope: every text file under the tree except
# markdown, docs/, and tool dirs (.git, .claude, node_modules, .venv). A comment line (first
# non-blank character `#` or `//`) is provenance prose and is skipped; so is a Python
# docstring (found with ast). Anything else that must keep a token (a check that greps for the
# token itself, an optional local-only test) carries the marker `boundary-ok: <reason>` on its
# line. No module is exempt: the four PATH-check exclusions above do not apply here.
#
# DATA: a runtime data path (a legacy default under ~/.claude, ~/.cache or ~/.config, listed in
# data_re) is spelled in ONE file, lib/config/data-path.sh. Anywhere else in executable code it
# is a hardcoded default that bypasses the resolver (SPEC-418), so a user cannot answer "where is
# my data" and `config data move` cannot carry it. Scope: lib/, hooks/, bin/, deploy/, install.sh,
# plus the agent-facing prose in commands/ and skills/ (a path printed there gets copied into a
# command). Skipped: the resolver itself, tests/, docs/, fixtures/ and examples/ dirs, other
# markdown, comment lines, Python docstrings. A line that must keep one carries `data-path-ok:
# <reason>`.
#
# name_files/name_re are a hand-maintained list, not derived from lib/config/module-
# registry.md's "## Seams" table: that table's Filled-by column is free-text prose ("the
# operator, for a skill that must read...") naming who fills a seam, not the compact retired-
# skill names this check greps for, so deriving one from the other would not be meaningful.
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ROOT is resolved to an absolute realpath (`cd ... && pwd`) even when passed relative (e.g.
# `boundary-lint.sh .`): the self-exclusion below matches grep hits by "$SELF/boundary-
# lint.sh:" prefix, which only lines up when ROOT and SELF share the same absolute form --
# a relative ROOT made grep emit "./lib/gate/boundary-lint.sh:" lines that never matched,
# so the lint flagged its own PATH-check example lines.
ROOT="$(cd "${1:-$SELF/../..}" && pwd)"
fail=0
flag() { printf 'boundary-lint: %s\n' "$1" >&2; fail=1; }

path_re='dotfiles/home|ops-toolkit/(tools|_meta)/'
path_excl=(--exclude-dir=plugin-check --exclude-dir=webcheck --exclude-dir=sync --exclude-dir=stats)
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  flag "consumer path hardcoded: $hit"
done < <(grep -rnE "${path_excl[@]}" "$path_re" \
  "$ROOT/lib" "$ROOT/hooks" "$ROOT/commands" "$ROOT/tests" "$ROOT/kit.toml" 2>/dev/null \
  | grep -v "^$SELF/boundary-lint.sh:" || true)

# Retired/pedagogy skill names (ROADMAP.md "Retired words" + the two names that migration moved
# behind the seam), checked only where this repo could plausibly still hardcode one.
name_re='narrate-log|svg-knowledge-diagram|deep-understand|dev-learner|session-closeout|session-distill|learning-ledger'
# Every commands/*.md file, not the three that existed when this list was written: a NEW
# command file hardcoding a retired name previously stayed green (the finding this closes).
# pitch.md is the one documented exception: it composes `narrate-log` for an unrelated
# feature (a real, legitimate hit, not a boundary violation), so it is excluded by name
# rather than silently dropped by a narrower glob.
name_files=("$ROOT/kit.toml" "$ROOT/lib/gate/quiz-gate.sh" "$ROOT/lib/gate/README.md")
while IFS= read -r -d '' f; do
  [ "$(basename "$f")" = "pitch.md" ] && continue
  name_files+=("$f")
done < <(find "$ROOT/commands" -maxdepth 1 -name '*.md' -print0 2>/dev/null)
while IFS= read -r -d '' f; do name_files+=("$f"); done \
  < <(find "$ROOT/lib/reflect" -type f -print0 2>/dev/null)

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  flag "consumer skill named directly: ${hit#"$ROOT/"}"
done < <(grep -nE "$name_re" "${name_files[@]}" 2>/dev/null || true)

# DENY check. The pattern is assembled from halves so this file is not its own hit.
deny_re="h""an-ws|tie""ubao|ops-""toolkit|op://""Toolkit"
deny_scan() {
  command -v python3 >/dev/null 2>&1 || { echo "needs python3 on PATH"; return 1; }
  python3 - "$ROOT" "$SELF/boundary-lint.sh" "$deny_re" <<'PY'
import ast, os, re, sys

root, self_path, pattern = sys.argv[1], sys.argv[2], sys.argv[3]
deny = re.compile(pattern, re.I)
skip_dirs = {".git", ".claude", "node_modules", ".venv", "__pycache__", "docs"}
skip_ext = {".md", ".lock", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg", ".pdf",
            ".woff", ".woff2", ".gz", ".zip", ".tar", ".tgz"}


def docstring_lines(text):
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError):
        return set()
    lines = set()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        body = node.body
        if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant) \
                and isinstance(body[0].value.value, str):
            lines.update(range(body[0].lineno, body[0].end_lineno + 1))
    return lines


for dirpath, dirs, files in os.walk(root):
    dirs[:] = sorted(d for d in dirs if d not in skip_dirs)
    for name in sorted(files):
        if name == ".git":  # a linked worktree's gitdir pointer file
            continue
        path = os.path.join(dirpath, name)
        if path == self_path or os.path.splitext(name)[1].lower() in skip_ext or os.path.islink(path):
            continue
        try:
            with open(path, "rb") as fh:
                raw = fh.read()
        except OSError:
            continue
        if b"\0" in raw:
            continue
        text = raw.decode("utf-8", "replace")
        first = text.split("\n", 1)[0]
        is_py = name.endswith(".py") or (first.startswith("#!") and "python" in first)
        skip = docstring_lines(text) if is_py else set()
        for n, line in enumerate(text.split("\n"), 1):
            stripped = line.lstrip()
            if n in skip or stripped.startswith("#") or stripped.startswith("//"):
                continue
            if deny.search(line) and "boundary-ok:" not in line:
                print(f"{os.path.relpath(path, root)}:{n}: {line.strip()[:160]}")
PY
}
# Captured, not piped through process substitution: a failed scan (no python3, a crash) must
# fail the lint, and a substitution's exit status is lost.
if deny_out="$(deny_scan)"; then
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    flag "operator identity in code: $hit"
  done <<< "$deny_out"
else
  flag "deny check could not run: $deny_out"
fi

# DATA check. Same shape as the deny scan: captured, so a crashed scan fails the lint.
data_re='\.claude/(dwarves-kit/state|dwarves-kit/tool-policy|intel|skill-proposals|skill-curator|logs/money-gate)|\.cache/(backlog-sync|claude-context-budget)|\.config/harvest-sweep'  # data-path-ok: the lint's own pattern
data_scan() {
  command -v python3 >/dev/null 2>&1 || { echo "needs python3 on PATH"; return 1; }
  python3 - "$ROOT" "$data_re" <<'PY'
import ast, os, re, sys

root, pattern = sys.argv[1], sys.argv[2]
pat = re.compile(pattern)
skip_dirs = {".git", ".claude", "node_modules", ".venv", "__pycache__", "docs", "tests", "fixtures", "examples"}
skip_ext = {".lock", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg", ".pdf",
            ".woff", ".woff2", ".gz", ".zip", ".tar", ".tgz"}
resolver = os.path.join(root, "lib", "config", "data-path.sh")
scan_dirs = [os.path.join(root, d) for d in ("lib", "hooks", "bin", "deploy", "commands", "skills")]
scan_files = [os.path.join(root, "install.sh")]


def docstring_lines(text):
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError):
        return set()
    lines = set()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        body = node.body
        if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant) \
                and isinstance(body[0].value.value, str):
            lines.update(range(body[0].lineno, body[0].end_lineno + 1))
    return lines


def candidates():
    for top in scan_dirs:
        for dirpath, dirs, files in os.walk(top):
            dirs[:] = sorted(d for d in dirs if d not in skip_dirs)
            for name in sorted(files):
                yield os.path.join(dirpath, name)
    for f in scan_files:
        if os.path.isfile(f):
            yield f


for path in candidates():
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1].lower()
    rel = os.path.relpath(path, root)
    prose = ext == ".md"
    if path == resolver or os.path.islink(path) or ext in skip_ext:
        continue
    if prose and not rel.startswith(("commands" + os.sep, "skills" + os.sep)):
        continue
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        continue
    if b"\0" in raw:
        continue
    text = raw.decode("utf-8", "replace")
    first = text.split("\n", 1)[0]
    is_py = name.endswith(".py") or (first.startswith("#!") and "python" in first)
    skip = docstring_lines(text) if is_py else set()
    for n, line in enumerate(text.split("\n"), 1):
        stripped = line.lstrip()
        if not prose and (n in skip or stripped.startswith("#") or stripped.startswith("//")):
            continue
        if pat.search(line) and "data-path-ok:" not in line:
            print(f"{rel}:{n}: {line.strip()[:160]}")
PY
}
if data_out="$(data_scan)"; then
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    flag "data path hardcoded outside lib/config/data-path.sh (use: config data path <kind> <name>): $hit"
  done <<< "$data_out"
else
  flag "data check could not run: $data_out"
fi

[ "$fail" = 0 ] && echo "boundary-lint: PASS"
exit "$fail"
