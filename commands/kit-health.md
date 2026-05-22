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

# 11. Release hygiene: a phantom version cut (VERSION names an untagged version)
# Repo-scoped: reads the repo's .git + VERSION via the current working dir (git
# tags + CHANGELOG live in the repo, not the installed copy under ~/.claude). The
# guard degrades to a no-op outside a git repo / without VERSION, never errors.
if [ -f VERSION ] && git rev-parse --git-dir >/dev/null 2>&1; then
  VER=$(tr -d '[:space:]' < VERSION)
  if [ -n "$VER" ] && [ -z "$(git tag -l "v$VER")" ]; then
    echo "  [WARN] release hygiene: VERSION is $VER but tag v$VER does not exist (phantom cut)"
    # Accumulation context: [Unreleased] NON-empty => work piling above an untagged cut (same awk as ship.md, DEC-006).
    if [ -f CHANGELOG.md ] && awk '/## \[Unreleased\]/{f=1;next} /^## /{f=0} f && NF{print}' CHANGELOG.md | grep -q .; then
      echo "         and CHANGELOG [Unreleased] is accumulating above it"
    fi
  else
    echo "  release hygiene: ok (v$VER tagged, or clean)"
  fi
else
  echo "  release hygiene: skipped (not in the kit repo / no VERSION)"
fi
```

### Step 2: Present health report

Format the results as a verdict, not a checklist. The kit is opinionated; the report should be too. The verdict is one of three values, evaluated against the gate rules below:

- **SHIP** -- all critical checks pass, no philosophy violations, no hook over 500ms, no compiled binaries.
- **FIX-REQUIRED** -- one or more non-critical checks fail OR there are TODOs/FIXMEs in hooks. Kit still works, but the failures must be addressed before the next release.
- **REJECT** -- one or more critical violations: a compiled binary present, a hook over 500ms, settings.json invalid, a registered hook missing, or any philosophy violation flagged in Step 3.

Output:

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
Verdict: SHIP / FIX-REQUIRED / REJECT
```

If the verdict is REJECT, surface the specific violation and what would need to change to lift it. kit-health is a self-diagnostic command, not a safety hook -- it labels the state clearly and recommends, but does not block (per `Detect, don't dictate`). The user decides whether to act. Reserve actual blocking for the safety-gate hook.

### Step 3: Philosophy alignment check

Review against PHILOSOPHY.md principles:

1. **Guardrails over guidance**: Are there any CLAUDE.md rules that should be hooks instead?
2. **Synthesize, don't originate**: Are there components without source citations?
3. **One kit, whole cycle**: Does docs/specs/SPEC-NNN-<slug>.md still flow through all commands?
4. **Bash over binaries**: Any non-bash hooks (except the statusline carve-out)?
5. **Detect, don't dictate**: Any hooks that block when they should suggest?
6. **External tools are dependencies**: Any rebuilt functionality that duplicates external tools?

Flag any violations and suggest fixes.

### Step 4: What this kit will reject

Borrowed in spirit from superpowers' AGENTS.md "What We Will Not Accept". The kit-health command is the in-repo voice that catches violations before they ship. The following are auto-REJECT conditions. State them when reviewing PRs, contractor work, or your own additions to the kit:

1. **Compiled binaries.** Bash is the carve-in, statusline.sh's optional `mjs` polyfill is the only carve-out (PHILOSOPHY.md `Bash over binaries`). Any new `.exe`, `.bin`, `.so`, `.dylib` in the kit directory is a REJECT, no exceptions.
2. **Hooks over 500ms.** Profile with `time` before merging. A slow hook degrades every session. (PHILOSOPHY.md `Maximum 500ms per hook execution`)
3. **No source citation.** Every component must trace to a proven implementation. Net-new patterns without lineage get rejected and routed to "test as a standalone experiment first" (PHILOSOPHY.md `Synthesize, don't originate`)
4. **Single-purpose features serving fewer than 2 of the 8 workflow phases.** Belongs as a standalone script, not a kit feature. (PHILOSOPHY.md feature rejection criterion 2)
   - *Exception (recorded):* `/user:visual-team` and `/user:ui-design` are downstream-facing (they serve UI-bearing consumer projects, not the kit's own phases) per `PHILOSOPHY.md` "Downstream-facing lanes". Do NOT flag them under this criterion. Any other single-purpose feature without a named downstream consumer still gets rejected here.
5. **Duplicates an external tool.** If chub, GSD, gstack, Trail of Bits, or a Claude Code plugin already does it, depend on it. Do not rebuild. (PHILOSOPHY.md `External tools are dependencies, not features`)
6. **Cannot be explained in one sentence.** If the README table can't fit it on one line, the component is too complex. (PHILOSOPHY.md feature rejection criterion 4)
7. **Non-bash hooks** (except the documented statusline carve-out). Adds runtime dependencies, slows startup, makes debugging harder. Per PHILOSOPHY.md: if a second exception is proposed, the `Bash over binaries` principle should be revisited entirely, not bent again. A second non-bash hook triggers REJECT until the principle is formally re-evaluated.
8. **Phantom features.** Documented but not implemented, or validated but not used. (CLAUDE.md template `No phantom features`)
9. **Speculative configuration.** Flags, options, or knobs added "in case we need them later". Build it when there's a real consumer.
10. **Bundled unrelated changes** in one PR. Split. One feature, one PR, one source citation.
11. **Vendor-skill sprawl.** Skills bundled to pad the catalog rather than serve 2+ phases from a single proven source. (PHILOSOPHY.md "What we explicitly reject (from upstream observation)")
12. **UI-shell creep.** A statusline/HUD grown into a stateful UI with caches, themes, or its own config surface. (PHILOSOPHY.md "What we explicitly reject (from upstream observation)")
13. **Agent-persona theater.** Agents named for personas ("studio", "agent company") instead of their function. (PHILOSOPHY.md "What we explicitly reject (from upstream observation)")
14. **Slop-PR submissions.** AI-generated PRs with no human involvement, or speculative fixes nobody asked for. (PHILOSOPHY.md "What we explicitly reject (from upstream observation)"; CONTRIBUTING.md AI-agent wall)

When kit-health detects any of these, the verdict is **REJECT**. Surface it to the user and recommend the fix path: either remove the violation or document an explicit carve-out in PHILOSOPHY.md with rationale. Do not paper over the finding silently.

### Step 5: Suggest maintenance actions

Based on the checks:
- If hook logs show zero activity for 30+ days on any hook, suggest deprecation review
- If file count is growing without justification, suggest a cleanup pass
- If TODOs exist in hooks, list them with context
- If performance is over 500ms on any hook, flag it for optimization

Source: superpowers v5.0.7 `AGENTS.md` -- the rejection-first verdict structure (`SHIP / FIX-REQUIRED / REJECT`) and the "What We Will Not Accept" framing in Step 4 are adapted from superpowers' contributor doc voice ("PRs that show no evidence of human involvement will be closed", "Speculative or theoretical fixes" rejection). Numbered violations grounded in our own PHILOSOPHY.md, not lifted verbatim.
