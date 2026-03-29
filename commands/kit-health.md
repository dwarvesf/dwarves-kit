---
description: "Run a self-assessment of the kit against its own philosophy. Checks file count, hook performance, source citations, and structural health."
---

You are running a health check on the dwarves-kit installation. This command evaluates the kit against its own design principles from PHILOSOPHY.md.

## Process

### Step 1: Run automated checks

Execute these checks and collect results:

```bash
# 1. File count
echo "Files: $(find ~/.claude/dwarves-kit -type f | grep -v '.git/' | wc -l)"

# 2. Hook executability
for f in ~/.claude/dwarves-kit/hooks/*.sh; do
  [ -x "$f" ] && echo "  [ok] $(basename $f)" || echo "  [FAIL] $(basename $f) not executable"
done

# 3. Settings.json validity
jq . ~/.claude/dwarves-kit/settings.json >/dev/null 2>&1 && echo "settings.json: valid" || echo "settings.json: INVALID"

# 4. All hooks in settings.json point to files that exist
jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | .command] | .[]' ~/.claude/dwarves-kit/settings.json | while read cmd; do
  SCRIPT=$(echo "$cmd" | sed "s|bash \$HOME|bash $HOME|" | awk '{print $2}')
  SCRIPT=$(eval echo "$SCRIPT")
  [ -f "$SCRIPT" ] && echo "  [ok] $SCRIPT" || echo "  [MISSING] $SCRIPT"
done

# 5. Hook performance (time each one with sample input)
for f in ~/.claude/dwarves-kit/hooks/*.sh; do
  NAME=$(basename "$f")
  case "$NAME" in
    anti-rationalization.sh)
      INPUT='{"stop_hook_active":false,"assistant_response":"test response"}';;
    safety-gate.sh|spec-drift-guard.sh)
      INPUT='{"tool_input":{"command":"ls","file_path":"test.ts"}}';;
    permission-auto-approve.sh)
      INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"}}';;
    slop-cleaner.sh)
      INPUT='{"stop_hook_active":false,"assistant_response":"done"}';;
    *)
      INPUT='{}';;
  esac
  ELAPSED=$( { time echo "$INPUT" | bash "$f" >/dev/null 2>&1; } 2>&1 | grep real | awk '{print $2}')
  echo "  $NAME: $ELAPSED"
done

# 6. No compiled binaries
BINS=$(find ~/.claude/dwarves-kit -type f \( -name "*.exe" -o -name "*.bin" -o -name "*.so" -o -name "*.dylib" \) | wc -l | tr -d ' ')
echo "Compiled binaries: $BINS"

# 7. Every command has a description in YAML frontmatter
for f in ~/.claude/dwarves-kit/commands/*.md; do
  DESC=$(grep '^description:' "$f" | head -1)
  [ -n "$DESC" ] && echo "  [ok] $(basename $f)" || echo "  [MISSING] $(basename $f) has no description"
done

# 8. Hook logs exist and show recent activity
LOG_DIR="$HOME/.claude/dwarves-kit/logs"
if [ -d "$LOG_DIR" ]; then
  for f in "$LOG_DIR"/*.log; do
    [ -f "$f" ] || continue
    LINES=$(wc -l < "$f" | tr -d ' ')
    LAST=$(tail -1 "$f" | cut -d'|' -f1 | tr -d ' ')
    echo "  $(basename $f): $LINES entries, last: $LAST"
  done
else
  echo "  No log directory yet (hooks haven't fired)"
fi

# 9. Source citations in README credits
CREDITS=$(sed -n '/## Credits/,/## /p' ~/.claude/dwarves-kit/README.md | grep -c '\[')
echo "Source citations in README: $CREDITS"

# 10. TODOs/FIXMEs in hook scripts
TODOS=$(grep -r "TODO\|FIXME" ~/.claude/dwarves-kit/hooks/ 2>/dev/null | wc -l | tr -d ' ')
echo "TODOs/FIXMEs in hooks: $TODOS"
```

### Step 2: Present health report

Format the results as a health report:

```
Kit Health Report (date)
================================
[PASS/FAIL] File count: N
[PASS/FAIL] All hooks executable
[PASS/FAIL] settings.json valid
[PASS/FAIL] All registered hooks exist
[PASS/FAIL] Hook performance (all under 500ms)
[PASS/FAIL] No compiled binaries
[PASS/FAIL] All commands have descriptions
[INFO]      Hook log activity
[INFO]      Source citations: N
[PASS/WARN] TODOs in hooks: N
================================
Score: X/Y checks passed
```

### Step 3: Philosophy alignment check

Review against PHILOSOPHY.md principles:

1. **Guardrails over guidance**: Are there any CLAUDE.md rules that should be hooks instead?
2. **Synthesize, don't originate**: Are there components without source citations?
3. **One kit, whole cycle**: Does .planning/SPEC.md still flow through all commands?
4. **Bash over binaries**: Any non-bash hooks (except the statusline carve-out)?
5. **Detect, don't dictate**: Any hooks that block when they should suggest?
6. **External tools are dependencies**: Any rebuilt functionality that duplicates external tools?

Flag any violations and suggest fixes.

### Step 4: Suggest maintenance actions

Based on the checks:
- If hook logs show zero activity for 30+ days on any hook, suggest deprecation review
- If file count is growing without justification, suggest a cleanup pass
- If TODOs exist in hooks, list them with context
- If performance is over 500ms on any hook, flag it for optimization
