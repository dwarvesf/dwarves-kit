# `fleet sync`: syncing skills to every harness

`fleet sync` reads `fleet.toml`, finds each skill's single-source `SKILL.md`,
validates it, and **generates** each target harness's loader from that one body.
It never hand-copies and it never silently overwrites a loader that someone has
edited by hand.

This doc covers how to run sync, the `--check` dry-run, what drift detection
does, and how to recover from the common failures. For the file formats
themselves see [SCHEMA.md](SCHEMA.md).

## Setup

`fleet sync` is a Core-tier, plain-file tool. It needs no network access and no
remote install — it reads and writes repositories on local disk.

1. **Have a `fleet.toml` at your registry root.** A minimal one:

   ```toml
   [fleet]
   version = "1.0.0"
   registry_name = "my-fleet"
   default_harnesses = ["cc", "codex", "opencode"]

   [[skills]]
   id = "github-pr-workflow"
   source = "skills/devops/github-pr-workflow/SKILL.md"
   version = "1.4.0"
   tier = "core"
   dependencies = ["gh", "git"]
   metadata = { category = "devops" }
   ```

   See [SCHEMA.md §3](SCHEMA.md) for every key, and the reference
   `fleet.toml` shipped at `fleet.toml` in this directory.

2. **Point `source` at a real `SKILL.md`.** The `source` path is resolved
   relative to `[fleet].skills_root` (default `.`, i.e. the directory containing
   `fleet.toml`). For a `core` skill, `source` must be a plain relative repo
   path — no `url:`, `private://`, or `http(s)://` (that is a V10 error). Craft
   skills may use `private://<stream>/...` or `url:<https>`; see
   [PRIVATE-STREAM.md](PRIVATE-STREAM.md).

3. **Run sync.** From the registry root:

   ```bash
   fleet sync
   ```

   With no arguments, sync validates every `[[skills]]` entry and writes the
   loaders for each skill's `harnesses`.

## Invocation

```bash
fleet sync [--check] [--registry PATH] [--only ID,...] [--harness cc,codex]
```

| Flag | Meaning |
|---|---|
| `--check` | Validate and report what *would* change, write nothing. See below. |
| `--registry PATH` | Use a `fleet.toml` at `PATH` instead of the one in the current directory. |
| `--only ID,...` | Restrict the run to the named skill ids (comma-separated). |
| `--harness cc,codex` | Override the harness set for this run (subset of the skill's declared harnesses). |

> Invocation note: the command is shown as `fleet sync`. When wired into an
> adopted repo it runs as the kit's `fleet` entrypoint; the bare form is used in
> this doc for readability.

## What a normal sync does

For each valid `[[skills]]` entry, sync:

1. Parses `fleet.toml` (V1) and checks `[fleet].version` (V2).
2. Validates the entry has `id`/`source`/`version` (V3), a well-formed unique
   `id` (V4), and known unique harnesses (V5).
3. Reads and validates the source `SKILL.md` (V6, V7) and checks the cross-file
   contract: `SKILL.md` `name` == `fleet` `id` (V8) and `version` == `fleet`
   `version` (V9). For `core` skills it also enforces the plain-file source
   constraint (V10) and local-CLI dependency rule (V11).
4. For each target harness, generates the loader (see the output map below).
5. Computes a checksum of each generated loader against the source and records
   it for next-run drift detection (V13).

### Output map

| Harness | Output path | Written content |
|---|---|---|
| `cc` | `<cc>/<category>/<id>/SKILL.md` | Verbatim copy of source `SKILL.md`. |
| `codex` | `<codex>/<id>.openai.yaml` (+ `<id>.md` sibling) | `openai.yaml` sidecar (name, version, description, file ref) + the `.md` copy. |
| `opencode` | `<opencode>/<category>/<id>/SKILL.md` | Verbatim copy of source `SKILL.md`. |

`<category>` is taken from `metadata.category`, falling back to the top-level
directory of `source`. The output roots (`cc`, `codex`, `opencode`) default to
`skills`, `codex`, `opencode` respectively and are configurable via
`[fleet.outputs]` (see [SCHEMA.md §3.2](SCHEMA.md)).

Because the loaders are generated, **none** of them is hand-authored — that is
what eliminates per-harness packaging.

## The `--check` flag (dry run)

`fleet sync --check` validates the registry and every source, and reports what
it *would* write, **without writing anything**. It is the safe way to verify a
`fleet.toml` change before committing loaders, and the form CI runs.

```bash
fleet sync --check
```

It reports, per skill:

- validation status (pass, or the failing rule id such as `V8`);
- for each harness, one of:
  - `new` — no loader exists yet; sync would create it;
  - `up-to-date` — an identical loader already exists;
  - `update` — a loader exists and would be regenerated (source changed);
  - `drift` — a loader exists, differs from source, and has local edits (see
    drift below); `--check` never resolves drift, it surfaces it.

Exit code: `0` if every entry is valid and every in-sync-or-new loader would be
written cleanly; **non-zero** if any entry fails validation (so CI can fail the
build) or if any skill is in `drift` (so a human looks before an overwrite).
`--check` still exits `0` when loaders would be freshly created — that is a
normal, non-destructive action.

Use it in a pre-push hook:

```bash
# .github/workflows/fleet.yml (illustrative)
- run: fleet sync --check
```

## Drift detection

"Drift" means a generated loader on disk no longer matches the source it was
generated from. There are two causes, and sync tells them apart because the
recovery is different:

| State | Cause | sync's behavior |
|---|---|---|
| **Stale** (`update`) | The source `SKILL.md` changed; the loader is behind. | Safe to regenerate. `fleet sync` overwrites it (no local edits were made to the loader). |
| **Drifted** (`drift`) | Someone edited the *generated loader* by hand, diverging from source. | **Never silently overwritten.** sync reports the conflict and stops touching that file. |

Detection is checksum-based (V13): when sync writes a loader it records a
checksum of the source-committed content. On the next run it compares the
on-disk loader's checksum against the source. A mismatch that is *not* explained
by a newer source is drift.

### What to do on drift

1. Read the report: sync prints which harness loader drifted and the path.
2. Decide the intent:
   - **The hand-edit was a fix** that belongs in the source: move the change
     into the canonical `SKILL.md`, then `fleet sync` regenerates cleanly.
   - **The hand-edit was a harness-specific tweak** that should not be in the
     shared body: that is a sign the skill needs a harness-specific override
     (out of scope for v1; tracked in the design brief) — for now, treat
     hand-edits to generated loaders as unsupported and revert them.
   - **The source is wrong** and the hand-edit is the real version: pull the
     change back into `SKILL.md`, bump `version`, and re-sync.
3. After reconciling, edit only `SKILL.md`, never the generated loader, then
   re-run `fleet sync`.

The principle: **generated files are not yours to edit.** They are disposable
outputs. The only authored artifact is `SKILL.md` + `fleet.toml`.

## Troubleshooting

| Symptom | Rule | Cause | Fix |
|---|---|---|---|
| `fleet.toml: parse error` | V1 | TOML syntax error (stray quote, bad array). | Run `fleet sync --check`; the parser points at the line. |
| `fleet[version]: missing or invalid` | V2 | `[fleet].version` absent or not semver. | Set `version = "1.0.0"`. |
| `skill X: missing id/source/version` | V3 | A `[[skills]]` entry lacks a required field. | Add the missing field. |
| `skill X: id 'GitHub PR' invalid` | V4 | `id` has spaces/caps or is too long. | Use `^[a-z0-9][a-z0-9-]{0,63}$`, e.g. `github-pr-workflow`. |
| `skill X: duplicate/unknown harness 'gemini'` | V5 | A harness appears twice or is not `cc`/`codex`/`opencode`. | Dedupe and use only the three known ids. |
| `skill X: source not found: <path>` | V6 | `source` does not resolve under `skills_root`. | Fix the path, or `skills_root`. |
| `skill X: SKILL.md missing required key` | V7 | Frontmatter lacks `name`/`description`/`version`/`author`/`license`/`platforms`. | Add the missing frontmatter keys (see [SCHEMA.md §4.1](SCHEMA.md)). |
| `skill X: name 'gh-pr' != fleet id 'github-pr-workflow'` | V8 | `SKILL.md` `name` and `fleet.toml` `id` disagree. | Make them identical. |
| `skill X: version 1.5.0 != fleet version 1.4.0` | V9 | `SKILL.md` `version` and `fleet.toml` `version` disagree. | Bump both to the same semver. |
| `skill X: core source must be a plain path` | V10 | A `core` skill uses `url:`/`private://`/`http(s)://`. | Move the content into the repo as a relative path, or set `tier = "craft"`. |
| `skill X: dependency 'pip-pkg' is a remote install` | V11 (warn) | A `core` skill depends on a package that needs a network install. | Use a local CLI (`gh`, `git`, `yt-dlp`), or set `tier = "craft"`. |
| `skill X: harness 'codex' runtime < min_version 0.30.0` | V12 | The installed harness runtime is older than the constraint. | Upgrade the harness, or relax `min_version`. (Reported/skipped, not fatal in v1.) |
| `skill X: drift in <harness> loader` | V13 | A generated loader was edited by hand. | Reconcile into `SKILL.md` (see Drift above); never edit the loader. |

### Common confusion

- **"I changed `SKILL.md` but the harness still shows the old text."** The
  loader is not live-linked to the source; you must run `fleet sync` to
  regenerate it. `fleet sync --check` first to confirm what will change.
- **"Sync overwrote my tweak!"** If it did, the loader was *stale*, not drifted
  — sync only overwrites when the source changed and the loader had no local
  edits. If you want a change to survive, put it in `SKILL.md`.
- **"My craft skill won't sync from `private://`."** Craft sources resolve
  through the private stream, not the local repo. See
  [PRIVATE-STREAM.md](PRIVATE-STREAM.md).
