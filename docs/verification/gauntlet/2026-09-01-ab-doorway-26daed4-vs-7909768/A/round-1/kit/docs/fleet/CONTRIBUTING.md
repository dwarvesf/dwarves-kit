# Contributing to the skill fleet

This doc is for contributors: people adding a skill to the registry, editing
the schema, or changing how sync generates loaders. For day-to-day operation see
[SYNC.md](SYNC.md); for the format spec see [SCHEMA.md](SCHEMA.md).

The fleet's golden rule, repeated from the schema: **one body, many loaders.**
You author exactly one `SKILL.md` per skill plus one `[[skills]]` row in
`fleet.toml`. Everything a harness consumes is *generated* from that pair. You
never hand-author a `cc` directory copy, a `codex` `openai.yaml`, or an
`opencode` copy.

## Adding a new skill (the happy path)

### 1. Author the canonical `SKILL.md`

One file per skill. Frontmatter is the machine contract (routing/versioning);
the body is the human contract.

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

One-shot lifecycle for shipping a change through GitHub. Does not merge for you;
it gates and hands you the merge decision. Depends on `gh` and `git`.

## When to Use
...
```

Rules (full list in [SCHEMA.md §4](SCHEMA.md)):

- `name` matches `^[a-z0-9][a-z0-9-]{0,63}$` and **equals** the `fleet.toml` `id`.
- `description` is ≤ 60 chars, one sentence, ends with `.`.
- `version` is SemVer and **equals** the `fleet.toml` `version`.
- `author` credits a human first, then `Hermes Agent`. Never `author: Hermes Agent` alone.
- `license` is an SPDX id. `platforms` is a subset of `[linux, macos, windows]`.

### 2. Register it in `fleet.toml`

```toml
[[skills]]
id = "github-pr-workflow"
source = "skills/devops/github-pr-workflow/SKILL.md"
version = "1.4.0"
tier = "core"
dependencies = ["gh", "git"]
metadata = { category = "devops", tags = ["github", "pr"], license = "MIT" }
```

- `id`, `source`, `version` are required (V3).
- `id` is unique and well-formed (V4).
- `harnesses` is optional; it defaults to `[fleet].default_harnesses`.
- `category` (in `metadata`) sets the output subdirectory; if omitted, sync
  falls back to the top-level directory of `source`.

### 3. Validate before committing

```bash
fleet sync --check
```

`--check` validates the whole registry and reports `new` / `up-to-date` /
`update` / `drift` per harness without writing. Green means safe to commit the
`fleet.toml` change (the generated loaders are produced at sync time, not
committed to the registry source).

### 4. Generate the loaders

```bash
fleet sync
```

Confirm the loaders appear under the configured output roots
(`skills/`, `codex/`, `opencode/` by default; see
[SCHEMA.md §3.2](SCHEMA.md)).

## Adding a Craft skill (stream-backed)

A Craft skill is declared with `tier = "craft"` and a `private://` or `url:`
source instead of a relative path. You do **not** author the `SKILL.md` in the
registry repo — it lives on the private stream. See
[PRIVATE-STREAM.md](PRIVATE-STREAM.md) for the full flow.

```toml
[[skills]]
id = "internal-deploy-runbook"
source = "private://skills/deploy/SKILL.md"
version = "0.9.0"
tier = "craft"
```

The cross-file contract (V8/V9) still applies: the stream's `SKILL.md` `name`
and `version` must match `fleet.toml`.

## Core-tier constraints (do not bypass)

If `tier` is omitted or `"core"` (the default), these hard constraints hold
([SCHEMA.md §3.5](SCHEMA.md), validation V10/V11):

- `source` **must** be a plain relative repo path. Forbidden prefixes:
  `url:`, `private://`, `http://`, `https://`.
- `source` must resolve to a file inside the repo (under `skills_root`).
- `dependencies` must name local CLIs/runtimes already on a standard dev
  machine (`gh`, `git`, `yt-dlp`). They must **not** name packages requiring a
  network install to consume the skill.
- The generated loaders must be plain files (`.md` / `.yaml`) — no embedded
  remote fetch, no wrapper that phones home.

If your skill needs a remote source or a network install, it is a **Craft**
skill, not core. Set `tier = "craft"`. Core exists to be the N4 adoption
driver: plain files, no external dependency at consume time.

## Versioning

- **Skill version** (`SKILL.md` `version` and `fleet.toml` `[[skills]].version`)
  is SemVer 2.0.0. `MAJOR` = breaking change, `MINOR` = backward-compatible
  addition, `PATCH` = fix/clarification. New skills start at `0.1.0`. The two
  values **must stay equal** (V8/V9).
- **Harness version constraint** (`harnesses[].min_version` / `max_version`)
  constrains the *harness runtime*, not the skill. Inclusive bounds.
- **Registry schema version** (`[fleet].version`) is the file-shape version.
  Pinned at `1.0.0` for the canonical release. Bump MAJOR only on a breaking
  change to the `fleet.toml` shape. It is distinct from every skill version.

## Changing the schema

The schema is the contract; changes ripple to the validator, the generator, and
this documentation. When you change `fleet.toml` or `SKILL.md` semantics:

1. Update [SCHEMA.md](SCHEMA.md) first — it is the canonical spec. Add a
   validation rule row (V1–V13 and beyond) with severity and location.
2. Add a valid example and, where the change introduces a new rejection, an
   invalid example in §8/§9.
3. Keep `fleet.schema.json` (the machine-readable JSON Schema, Draft 2020-12)
   in sync with the prose. It is the artifact CI can check a `fleet.toml`
   against directly.
4. Update the relevant operator doc ([SYNC.md](SYNC.md) for behavior,
   [PRIVATE-STREAM.md](PRIVATE-STREAM.md) for Craft, this file for the
   contributor path).
5. Bump `[fleet].version` only on a breaking file-shape change.

The acceptance-criteria traceability table at the bottom of SCHEMA.md maps each
criterion to where it is satisfied — extend it when you add a rule.

## Reference artifacts in this directory

| File | What it is |
|---|---|
| `SCHEMA.md` | Canonical `fleet.toml` + `SKILL.md` schema spec (v1.0.0). |
| `fleet.schema.json` | Machine-readable JSON Schema (Draft 2020-12) for `fleet.toml`. |
| `fleet.toml` | Reference registry exercising all three harnesses and both tiers. |
| `README.md` | Index into this doc set. |
| `SYNC.md` | `fleet sync` usage, `--check`, drift, troubleshooting. |
| `PRIVATE-STREAM.md` | Craft private-stream integration. |
| `CONTRIBUTING.md` | This file. |
