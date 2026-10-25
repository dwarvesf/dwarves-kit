#!/usr/bin/env bash
# test-release.sh -- bin/release --dry-run against a fixture repo (ID-648).
# Pins: the root CHANGELOG.md is the roll target, the section
# header uses a hyphen separator (not a stray comma), the third version
# surface tool.toml moves with VERSION/plugin.json, and --dry-run restores
# every touched file leaving the tree clean.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$FIX"' EXIT

mkdir -p "$FIX/bin" "$FIX/.claude-plugin"
cp "$KIT_DIR/bin/release" "$FIX/bin/release"
chmod +x "$FIX/bin/release"
echo "1.0.0" > "$FIX/VERSION"
printf '{"name":"fixture","version":"1.0.0"}\n' > "$FIX/.claude-plugin/plugin.json"
printf 'name    = "fixture"\nversion     = "1.0.0"\n' > "$FIX/tool.toml"
cat > "$FIX/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- something pending

## [1.0.0] - 2026-01-01

- first cut
EOF

git -C "$FIX" init -q
git -C "$FIX" -c user.email=t@t -c user.name=t add -A
git -C "$FIX" -c user.email=t@t -c user.name=t commit -qm init >/dev/null

OUT="$("$FIX/bin/release" 1.1.0 --dry-run 2>&1)"

if echo "$OUT" | grep -q "tool.toml"; then
  ok "--dry-run reports the tool.toml surface"
else
  no "--dry-run silent on the tool.toml surface (SPEC-115 3-surface pin)"
fi

if echo "$OUT" | grep -q "CHANGELOG.md"; then
  ok "--dry-run reports CHANGELOG.md as the roll target"
else
  no "--dry-run did not name CHANGELOG.md as the roll target"
fi

if git -C "$FIX" diff --quiet -- VERSION .claude-plugin/plugin.json tool.toml CHANGELOG.md; then
  ok "--dry-run leaves the tree clean (files restored)"
else
  no "--dry-run left the tree dirty"
fi

# A real (non-dry) cut on a copy: verify the section header separator and
# that CHANGELOG.md actually changed on disk.
cp -R "$FIX" "$FIX.wet"
WET_OUT="$("$FIX.wet/bin/release" 1.1.0 2>&1)"

if grep -qE '^## \[1\.1\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$FIX.wet/CHANGELOG.md"; then
  ok "section header uses a hyphen separator, not a stray comma"
else
  no "section header separator wrong: $(grep '## \[1.1.0\]' "$FIX.wet/CHANGELOG.md" || echo '(not found)')"
fi

if grep -q '"version": "1.1.0"' "$FIX.wet/tool.toml" 2>/dev/null; then
  no "tool.toml regex over-matched plugin.json-style quoting"
elif grep -qE '^version\s*=\s*"1\.1\.0"' "$FIX.wet/tool.toml"; then
  ok "tool.toml version bumped to match VERSION (3-surface pin)"
else
  no "tool.toml version was not bumped"
fi

# Negative control: a benign file untouched by the release surfaces stays
# exactly as written -- proves the fixture isn't rigged to always pass.
if grep -q '"fixture"' "$FIX.wet/.claude-plugin/plugin.json"; then
  ok "negative control: unrelated plugin.json field left alone"
else
  no "negative control failed: unrelated field was touched"
fi

rm -rf "$FIX.wet"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
