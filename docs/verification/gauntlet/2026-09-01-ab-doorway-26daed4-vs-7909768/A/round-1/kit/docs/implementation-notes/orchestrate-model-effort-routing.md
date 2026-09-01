# Impl notes: per-sub-goal model/effort routing (SG-03)

Delta from SPEC-087. The spec adds a routing section (this PR); only off-spec calls live here.

## 2026-06-29 effort flag exists on the CLI
- Context: goal file said "pass `--model <tier>` + effort"; effort flag was unverified.
- Decision: pass both `--model` and `--effort` to `claude -p`. Verified `claude --version`
  2.1.195 exposes both `--model <model>` and `--effort <level>`. No custom plumbing needed.
- Why: the goal warned effort tiering might not have a stable CLI flag yet; it does.

## 2026-06-29 field read = grep, inherit-on-absent
- Decision: read `Model:`/`Effort:` from the goal file with a case-insensitive `grep` on a
  line-anchored `^Model:` / `^Effort:`, first match, value trimmed. Absent field or absent
  goal file -> empty -> no flag emitted (session inherits parent tier).
- Why: matches the existing goal-file `Key: value` convention; no frontmatter parser needed.
- Alternative rejected: a full YAML frontmatter parse, the goal files are not YAML; the
  fields are bare `Key: value` lines in the header.
