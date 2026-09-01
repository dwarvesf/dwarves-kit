# Skill Fleet Schema Specification

*Canonical schema reference for the skill fleet. This is the format spec;
[README.md](README.md) is the index, [SYNC.md](SYNC.md) covers `fleet sync`,
[PRIVATE-STREAM.md](PRIVATE-STREAM.md) covers the Craft private stream, and
[CONTRIBUTING.md](CONTRIBUTING.md) covers adding skills.*

**Schema version: `1.0.0`** · **Status: canonical** ·
**Owner: t_3dd38adf** (root of the fleet decomposition)

This document is the single source of truth for two formats:

1. **`fleet.toml`** — the registry that says *which* skills go to *which*
   harnesses, at *what* version, from *what* single source.
2. **`SKILL.md`** — the canonical per-skill body. Exactly **one** of these exists
   per skill. Every harness loader is *generated* from it.

Design goal (from the brief): generalize mattpocock's dual-harness pattern to
**all** listed harnesses from a single source. No per-harness packaging. The
**core tier is plain files only** (N4 adoption driver) — no external install, no
network dependency at consume time. "Craft" skills may ride the private stream.

---

## 1. Guiding principles

- **One body, many loaders.** Author a skill once (`SKILL.md`). `fleet sync`
  emits the CC directory copy, the Codex `openai.yaml` sidecar, and the
  opencode skill directory. Editing the skill means editing one file.
- **Registry is declarative, not imperative.** `fleet.toml` declares intent;
  the engine generates. It never stores generated content.
- **Drift is detected, never silent.** Generated files are checksummed against
  the source. A changed source that disagrees with an on-disk generated loader
  is reported before any overwrite (see `t_ce555189`).
- **Core = plain files, N4.** A `tier = "core"` skill's `source` MUST be a
  plain relative repo path. No `url:`, no `private://`, no runtime package
  fetch. Core `dependencies` MUST be local CLIs, not `pip install` targets.

---

## 2. Supported harnesses

| `harness` id | Full name            | Generated loader format                              |
|--------------|----------------------|-----------------------------------------------------|
| `cc`        | Claude Code / CC dir | `<cc>/<category>/<id>/SKILL.md` (directory skill)   |
| `codex`     | OpenAI Codex         | `<codex>/<id>.openai.yaml` (+ sibling `.md`)        |
| `opencode`  | pi / opencode        | `<opencode>/<category>/<id>/SKILL.md`               |

---

## 3. `fleet.toml` schema

### 3.1 `[fleet]` table (registry-global)

| Key                | Type            | Required | Default                       | Rules |
|--------------------|-----------------|----------|-------------------------------|-------|
| `version`          | `string` (semver) | yes    | —                             | Registry schema version. **Pin `1.0.0`.** Bump MAJOR on a breaking file-shape change. This is *not* a skill version. |
| `registry_name`    | `string` (1–128)  | yes    | —                             | Human label used in drift/catalog output. |
| `default_harnesses`| `array<string>`   | no     | `["cc","codex","opencode"]`   | Harness ids applied to any `[[skills]]` that omits `harnesses`. Entries must be unique and drawn from §2. |
| `skills_root`      | `string`          | no     | `"."`                         | Base dir (relative to `fleet.toml`) for resolving `source` and writing loaders. |

### 3.2 `[fleet.outputs]` table (optional)

Maps each harness id to a relative output directory. Defaults shown.

| Key        | Default     | Meaning |
|------------|-------------|---------|
| `cc`       | `"skills"`  | CC skills root. |
| `codex`    | `"codex"`   | Codex sidecars root. |
| `opencode` | `"opencode"`| opencode skills root. |

### 3.3 `[[skills]]` array (one entry per skill)

| Key            | Type                  | Required | Default           | Rules |
|----------------|-----------------------|----------|-------------------|-------|
| `id`           | `string`              | yes      | —                 | Unique skill id. **MUST equal** the `name` in the source `SKILL.md` frontmatter. Pattern: `^[a-z0-9][a-z0-9-]{0,63}$`. |
| `source`       | `string`              | yes      | —                 | Resolves the canonical `SKILL.md`. Core tier: a plain relative repo path. Craft tier: may use `private://<stream>/...` or `url:<https>`. |
| `version`      | `string` (semver)     | yes      | —                 | Pinned skill version. **MUST equal** `source` `SKILL.md` `version`. |
| `harnesses`    | `array`               | no       | `default_harnesses` | Non-empty list of harness targets. Each element is either a bare id (`"cc"`) or a table `{ name, min_version?, max_version? }`. Unique ids. |
| `tier`         | `"core" \| "craft"`   | no       | `"core"`          | `core` ⇒ plain-file / N4 rules (§3.5) enforced. |
| `dependencies` | `array<string>`       | no       | `[]`              | Local CLIs/runtimes the skill needs (informational + drift-checked). Core: no remote-install targets. |
| `metadata`     | `table`               | no       | `{}`              | Free-form. Recommended keys: `category`, `tags`, `maintainers`, `license`. |

### 3.4 `harnesses` element forms

```toml
# bare id — any version
harnesses = ["cc", "codex", "opencode"]

# table form — adds a version constraint
harnesses = [
  "cc",
  { name = "codex", min_version = "0.30.0" },
  { name = "opencode", min_version = "1.0.0", max_version = "1.9.9" },
]
```

- `name` ∈ {`cc`, `codex`, `opencode`}.
- `min_version` / `max_version` are semver strings (inclusive).
- A harness must appear **at most once** across the array.

### 3.5 Core-tier (N4) hard constraints

If `tier` is omitted or `"core"`:

- `source` MUST be a relative repo path (no scheme). Forbidden prefixes:
  `url:`, `private://`, `http://`, `https://`.
- `source` MUST resolve to a file inside the repo (under `skills_root`).
- `dependencies` entries MUST name local CLIs / runtimes already present on a
  standard dev machine (e.g. `gh`, `git`, `yt-dlp`). They MUST NOT name
  packages that require a network install to consume the skill.
- The generated loaders MUST be plain files (`.md` / `.yaml`), no embedded
  remote fetch, no wrapper that phones home.

`craft` tier is exempt and may reference the private stream.

---

## 4. `SKILL.md` canonical format (single source)

One file per skill. Frontmatter is the **machine contract**; the body is the
**human contract**. `fleet sync` reads frontmatter for routing/versioning and
copies the whole file (frontmatter + body) into each loader.

### 4.1 Required frontmatter

```yaml
---
name: <id>                 # lowercase, hyphens, ≤64 chars; MUST equal fleet.toml `id`
description: "One sentence, ≤60 chars, ends with a period."
version: <semver>          # MUST equal fleet.toml `version` for this skill
author: Real Name (handle), Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Short, Tags]
    related_skills: [other-skill]
---
```

| Field        | Required | Rules |
|--------------|----------|-------|
| `name`       | yes      | `^[a-z0-9][a-z0-9-]{0,63}$`. **Equals `fleet.toml` `id`.** |
| `description`| yes      | ≤ 60 chars, one sentence, ends with `.`. No marketing words. Wrap in quotes if it contains `:`. |
| `version`    | yes      | Semver. **Equals `fleet.toml` `version`.** |
| `author`     | yes      | Credit a human first, then `Hermes Agent`. Never `author: Hermes Agent` alone. |
| `license`    | yes      | SPDX id (`MIT`, `Apache-2.0`, `UNLICENSED`, …). |
| `platforms`  | yes      | Subset of `[linux, macos, windows]`, audited from the script/tool use. |
| `metadata.hermes.tags`      | no | Informational tags for the catalog. |
| `metadata.hermes.related_skills` | no | In-repo skill ids only. |

### 4.2 Body structure (recommended order)

```
# <Skill> Skill
2–3 sentence intro: what it does, what it doesn't do, dependency stance.

## When to Use          - triggers (+ "Don't use for:" counter-triggers)
## Prerequisites        - exact env vars, installs, API key sourcing
## How to Run           - canonical invocation
## Pitfalls             - version traps, gotchas, don'ts
## References           - pointers to references/ templates/ scripts/ (optional)
```

### 4.3 Global validation rules (all tiers)

1. File starts with `---` as the first bytes (no leading blank line) and closes
   with `\n---\n` before the body.
2. Frontmatter parses as a YAML mapping.
3. `name`, `description`, `version`, `author`, `license`, `platforms` present.
4. `description` ≤ 60 chars; ends with `.`.
5. Non-empty body after the closing `---`.
6. Full file ≤ 100,000 chars (target ~100 lines simple / ~200 complex).
7. Cross-file: `SKILL.md` `name` == `fleet.toml` `id`; `SKILL.md` `version` ==
   `fleet.toml` `version`. Mismatch ⇒ registry is invalid (rejected by `fleet sync`).

---

## 5. How `fleet sync` maps one source → three loaders

For a `[[skills]]` entry with `category` taken from `metadata.category`
(fallback: top-level dir of `source`):

| Harness  | Output path                                            | What is written |
|----------|--------------------------------------------------------|-----------------|
| `cc`     | `<cc>/<category>/<id>/SKILL.md`                        | Verbatim copy of source `SKILL.md`. |
| `codex`  | `<codex>/<id>.openai.yaml` (+ `<id>.md` sibling)       | `openai.yaml` sidecar (name, version, description, file ref) + the `.md` copy. |
| `opencode`| `<opencode>/<category>/<id>/SKILL.md`                 | Verbatim copy of source `SKILL.md`. |

Because the loaders are generated, **none** of them is hand-authored — that is
what eliminates per-harness packaging. See `examples/` for a concrete run.

---

## 6. Versioning scheme

- **Skill version** (`SKILL.md` `version` and `fleet.toml` `[[skills]].version`):
  **SemVer 2.0.0** (`MAJOR.MINOR.PATCH`).
  - `MAJOR`: breaking change to the skill's behavior or interface.
  - `MINOR`: backward-compatible addition.
  - `PATCH`: fixes/clarifications.
  - New skills start at `0.1.0`.
- **Harness version constraint** (`harnesses[].min_version` / `max_version`):
  SemVer, interpreted against the *harness runtime* version
  (`cc`, `codex`, `opencode`), not the skill version. Inclusive bounds.
- **Registry schema version** (`[fleet].version`): SemVer of this file shape.
  Pinned at `1.0.0` for the canonical release.

---

## 7. Validation rules summary (engine MUST enforce)

| # | Rule | Severity | Where |
|---|------|----------|-------|
| V1 | `fleet.toml` parses as TOML | error | fleet |
| V2 | `[fleet].version` present, valid semver | error | fleet |
| V3 | every `[[skills]]` has `id`, `source`, `version` | error | fleet |
| V4 | `id` matches `^[a-z0-9][a-z0-9-]{0,63}$` and is unique | error | fleet |
| V5 | every `harnesses` entry ∈ {cc,codex,opencode}, unique | error | fleet |
| V6 | `source` file exists & is readable | error | fleet→source |
| V7 | `SKILL.md` frontmatter has required keys (§4.3) | error | source |
| V8 | `SKILL.md` `name` == `fleet` `id` | error | cross-file |
| V9 | `SKILL.md` `version` == `fleet` `version` | error | cross-file |
| V10 | core tier: `source` is plain relative path (no scheme) | error | fleet |
| V11 | core tier: `dependencies` are local CLIs (no remote-install) | warn | fleet |
| V12 | harness runtime satisfies `min_version`/`max_version` at sync time | skip/ warn | engine×runtime |
| V13 | generated loader checksum matches source after sync (drift) | report | drift (t_ce555189) |

---

## 8. Valid examples

### 8.1 `fleet.toml` — valid

```toml
[fleet]
version = "1.0.0"
registry_name = "dwarves-kit-fleet"
default_harnesses = ["cc", "codex", "opencode"]

[[skills]]
id = "github-pr-workflow"
source = "skills/devops/github-pr-workflow/SKILL.md"
version = "1.4.0"
tier = "core"
dependencies = ["gh", "git"]
metadata = { category = "devops", tags = ["github", "pr"], license = "MIT" }
```

### 8.2 `SKILL.md` — valid (canonical)

```markdown
---
name: github-pr-workflow
description: "Carry a GitHub PR from branch to merge with CI gating."
version: 1.4.0
author: Tieubao (tieubao), Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [github, pr, ci]
---

# GitHub PR Workflow

One-shot lifecycle for shipping a change through GitHub.
...
```

See `examples/skills/devops/github-pr-workflow/SKILL.md` for the full body and
`examples/generated/{cc,codex,opencode}/...` for the three loader outputs.

---

## 9. Invalid examples (rejected by the engine)

### 9.1 `fleet.toml` — invalid (V4: bad id; V3: missing version)

```toml
[[skills]]
id = "GitHub PR Workflow"     # V4: space + caps, not ^[a-z0-9][a-z0-9-]{0,63}$
source = "skills/devops/github-pr-workflow/SKILL.md"
# V3: `version` missing
```

### 9.2 `fleet.toml` — invalid (V5: duplicate + unknown harness)

```toml
[[skills]]
id = "youtube-content"
source = "skills/research/youtube-content/SKILL.md"
version = "2.1.0"
harnesses = ["cc", "cc", "gemini"]   # V5: "cc" duplicated, "gemini" not a known harness
```

### 9.3 `fleet.toml` — invalid (V10: core tier with remote source)

```toml
[[skills]]
id = "internal-deploy-runbook"
source = "https://example.com/skills/deploy/SKILL.md"  # V10: core tier forbids url:
version = "0.9.0"
tier = "core"
```

### 9.4 `SKILL.md` — invalid (V8/V9: name+version mismatch with registry)

```markdown
---
name: gh-pr                      # V8: must equal fleet id "github-pr-workflow"
description: "Carry a GitHub PR from branch to merge with CI gating."
version: 1.5.0                   # V9: must equal fleet version 1.4.0
author: Tieubao (tieubao), Hermes Agent
license: MIT
platforms: [linux, macos]
---
```

### 9.5 `SKILL.md` — invalid (§4.3: description too long, no closing `---`)

```markdown
---
name: spike
description: "Use this skill when the user wants to feel out an idea before committing to a real build by validating feasibility, comparing approaches, and surfacing unknowns."  # > 60 chars
version: 1.0.0
author: Hermes Agent              # no human credited
license: MIT
platforms: [linux, macos, windows]
# missing closing --- before body
```

---

## 10. Acceptance-criteria traceability

| Criterion | Where satisfied |
|-----------|-----------------|
| Schema documentation complete | §1–§7 |
| Valid + invalid examples | §8, §9 |
| Validation rules unambiguous | §3.5, §4.3, §7 |
| All harnesses have example entries | `fleet.toml` ex1 (all 3), ex2 (cc+codex), ex3; `examples/generated/` |
| Eliminates per-harness packaging | §1, §5 (single source, generated loaders) |
| Core tier plain files, no external deps | §3.5 (V10/V11), ex1 |
