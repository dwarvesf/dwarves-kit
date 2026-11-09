#!/usr/bin/env bash
# requires: uv
# The proposed-row home repo is operator config, not code: [stats] home_repo in the operator
# kit.toml, empty by default. Empty means the staged block carries no Home line and nothing crashes.
#   H1  unset: config.home_repo() is empty
#   H2  an operator kit.toml sets it: config.home_repo() returns the value
#   H3  a project .kit.toml cannot set it (root-only read)
#   H4  an Anomaly built with an empty home stages a block with no `- Home:` line
#   H5  an Anomaly built with the configured home stages a `- Home: <value>` line
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
PASS=0; FAIL=0
ok()  { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
T="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/none" "$T/op" "$T/proj"

probe() { # probe <operator-dir> <project-dir> -> prints home_repo()
  KIT_CONFIG_ROOT="$T/none" KIT_CONFIG_OPERATOR="$1" KIT_PROJECT_ROOT="$2" \
    uv run python3 -c 'import sys; sys.path.insert(0, "src"); from stats import config; print(config.home_repo())'
}
stage() { # stage <home> -> prints the staged block
  uv run python3 - "$T" "$1" <<'PY'
import sys
sys.path.insert(0, "src")
from stats.anomalies import Anomaly, stage_proposals
t, home = sys.argv[1], sys.argv[2]
a = Anomaly(key="k", title="Home fixture anomaly", intent="i", approach="a", tags="#u-mid #f-mid",
            home=home, metric="m=1")
stage_proposals([a], f"{t}/staging-{'set' if home else 'empty'}.md", f"{t}/BACKLOG.md", date="2026-07-04")
print(open(f"{t}/staging-{'set' if home else 'empty'}.md").read())
PY
}

[ -z "$(probe "$T/none" "$T/none")" ] && ok "H1 unset -> empty" || bad "H1 unset -> empty"

printf '[stats]\nhome_repo = "acme-app"\n' > "$T/op/kit.toml"
[ "$(probe "$T/op" "$T/none")" = "acme-app" ] && ok "H2 operator toml sets it" || bad "H2 operator toml sets it"

printf '[stats]\nhome_repo = "evil-repo"\n' > "$T/proj/.kit.toml"
[ "$(probe "$T/none" "$T/proj")" = "" ] && ok "H3 project toml ignored" || bad "H3 project toml ignored"

out="$(stage "")"
case "$out" in *"## [staged] Home fixture anomaly"*) ok "H4 block staged with empty home";; *) bad "H4 block staged with empty home";; esac
case "$out" in *"- Home:"*) bad "H4 empty home must omit the Home line";; *) ok "H4 no Home line";; esac

out="$(stage "acme-app")"
case "$out" in *"- Home: acme-app"*) ok "H5 Home line carries the value";; *) bad "H5 Home line carries the value";; esac

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
