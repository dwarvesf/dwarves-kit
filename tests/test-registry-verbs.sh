#!/usr/bin/env bash
# test-registry-verbs.sh -- the Verbs kind of lib/registry/feature-registry.sh.
# A lib verb is listed when its script carries `# kit-verb: <name> | <description>` in its
# first 40 lines. Cases 1-6 drive a COPY of the generator in a throwaway tree (a handful of
# stub files, well under a second); case 7 pins the real kit: every declared verb has one line
# in docs/workflow-paths.md and vice versa.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
REG="lib/registry/feature-registry.sh"

D="$(mktemp -d)"
mkdir -p "$D/lib/registry" "$D/lib/x" "$D/commands" "$D/agents" "$D/skills/demo" "$D/hooks" "$D/docs/specs" "$D/tests"
cp "$KIT/$REG" "$D/$REG"
printf -- '---\ndescription: a stub command\n---\nbody\n' > "$D/commands/demo.md"
printf -- '---\ndescription: a stub agent\n---\nbody\n' > "$D/agents/demo-agent.md"
printf -- '---\ndescription: a stub skill\n---\nbody\n' > "$D/skills/demo/SKILL.md"
printf '#!/bin/bash\n# demo-hook.sh -- a stub hook\n' > "$D/hooks/demo-hook.sh"
printf '{"hooks":{}}\n' > "$D/hooks/hooks.json"
printf '{}\n' > "$D/settings.json"
gen() { ( cd "$D" && bash "$REG" generate "$D/out.md" ) && sed -n '/^## Verbs/,$p' "$D/out.md"; }

# 1. no marker, no verb rows
gen | grep -q '^| `' && no "1 no marker lists nothing" || ok "1 no marker lists nothing"

# 2. one marker, one row with source and description
printf '#!/usr/bin/env bash\n# foo.sh -- x\n# kit-verb: foo run | runs the foo thing\n' > "$D/lib/x/foo.sh"
printf 'SPEC-900 covers foo run.\n' > "$D/docs/specs/SPEC-900-foo.md"
printf 'foo.sh is exercised here\n' > "$D/tests/test-foo.sh"
OUT="$(gen)"
echo "$OUT" | grep -qF '| `foo run` | `[V]` | `lib/x/foo.sh` | runs the foo thing | SPEC-900 | test-foo.sh |' \
  && ok "2 marker becomes a row with source, spec and test refs" || { no "2 marker becomes a row"; echo "$OUT"; }

# 3. two markers in one file, two rows
printf '#!/usr/bin/env bash\n# kit-verb: bar a | first\n# kit-verb: bar b | second\n' > "$D/lib/x/bar.sh"
OUT="$(gen)"
{ echo "$OUT" | grep -qF '`bar a`' && echo "$OUT" | grep -qF '`bar b`'; } \
  && ok "3 several markers in one script give several rows" || no "3 several markers"

# 4. NEGATIVE CONTROL: remove the marker, the row disappears
printf '#!/usr/bin/env bash\n# foo.sh -- x\n' > "$D/lib/x/foo.sh"
echo "$(gen)" | grep -qF '`foo run`' && no "4 removed marker still listed" || ok "4 removed marker drops the row"

# 5. a marker past line 40 is prose, not a declaration
{ printf '#!/usr/bin/env bash\n'; for _ in $(seq 1 45); do echo '# filler'; done; echo '# kit-verb: late | too far down'; } > "$D/lib/x/late.sh"
echo "$(gen)" | grep -qF '`late`' && no "5 marker past line 40 listed" || ok "5 marker past line 40 is ignored"

# 6. a marker inside a tests/ fixture path still only counts under lib/: none outside lib/
printf '#!/usr/bin/env bash\n# kit-verb: outside | not under lib\n' > "$D/hooks/outside.sh"
echo "$(gen)" | grep -qF '`outside`' && no "6 marker outside lib listed" || ok "6 marker outside lib/ is ignored"

# 7. real kit: verb rows and path-index verb lines agree
F="$KIT/docs/FEATURES.md"; W="$KIT/docs/workflow-paths.md"
sed -n '/^## Verbs/,$p' "$F" | sed -nE 's/^\| `([^`]+)` \| `\[V\]`.*/\1/p' | sort > "$D/f-verb"
sed -n '/^### Verbs/,/^## 6/p' "$W" | grep -E '^\| `\[V\] ' | sed -E 's/^\| `\[V\] //; s/ ->.*//' | sort > "$D/w-verb"
if [ -s "$D/f-verb" ] && diff -q "$D/f-verb" "$D/w-verb" >/dev/null; then
  ok "7 every FEATURES verb has one path-index line ($(wc -l < "$D/f-verb" | tr -d ' ') verbs)"
else
  no "7 verb parity"; diff "$D/f-verb" "$D/w-verb"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
