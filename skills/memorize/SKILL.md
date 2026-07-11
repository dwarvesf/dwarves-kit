---
name: memorize
description: Use when the user wants something saved or remembered for later and does NOT name a destination, "save this", "remember this", "note this for next time", "don't forget this", "lưu", "nhớ cái này", or any bare save-intent in any language. ALSO fire proactively (without a save word) when the user corrects a fact the agent got wrong, states a durable preference, or renames something, that class of correction must persist without being asked. Routes the fact to the right durable store per the routing table (repo memory, user-global CLAUDE.md, machine-local memory, a prose-rag corpus dir, or a consumer capture skill), dedups against existing notes first, and reports where it landed and why in one line. NOT for content with an obvious domain home (a task for the backlog, a ledger row, a link to triage), route those to their owning skill or tool instead.
disable-model-invocation: false
---

# memorize (the save-router)

One interface for "save this". Decide by the FACT's scope, never by where the chat
happens to be. When the user says "save to memory" they mean the right memory, not
literally one file; picking the store is this skill's job. The user never needs to
name a destination; a bare save-intent is the whole interface.

## Routing table

| The fact is... | Destination | Mechanics |
|---|---|---|
| Repo-scoped (a gotcha, deploy lesson, ongoing-work state of ONE repo) | `<repo>/.claude/memory/<slug>.md` + one index line in `<repo>/.claude/memory/MEMORY.md` | git-tracked, syncs across machines; same frontmatter as built-in memories; commit rides the session's normal close |
| Cross-repo / global (a rule, preference, identity fact, tool default) | the user's `~/.claude/CLAUDE.md` | if that file is under config management (chezmoi, a dotfiles repo), edit the SOURCE and apply + commit atomically, never the rendered copy |
| True on THIS machine only | built-in auto-memory (`~/.claude/projects/<slug>/memory/`) | per-machine scratch, never synced; use only when the fact is genuinely per-box |
| A prose note (research finding, knowledge note, dated snapshot) | a directory on the `PROSE_RAG_CORPUS` path | write the note there, then run `prose-rag index` so it is searchable immediately |
| Covered by a consumer capture skill (a learning ledger, a public knowledge base) | delegate to that skill | it owns its own dedup + routing |

## RAG is an index, not a store

`prose-rag` indexes the corpus named by `PROSE_RAG_CORPUS` (consumer config, see
`lib/prose-rag/README.md`). "Save to RAG" therefore means: write the note into a
corpus directory per the table above, then run `prose-rag index`. Repo memory and
CLAUDE.md are NOT in the RAG index; they load via session hooks instead.

## Rules

1. **Dedup before writing.** Search the target store (and its index) for an existing
   note covering the fact; update that file instead of creating a sibling. Delete or
   amend notes the new fact proves wrong, in the same pass.
2. **Ambiguous scope defaults to repo memory** of the repo the fact is ABOUT (not the
   cwd). Git-tracked beats machine-local; machine-local is only for facts that are
   genuinely per-box.
3. **A wrong recall has a root cause.** When the trigger was the user correcting a bad
   recall, also fix the SOURCE that misled (a stale doc line, an old research
   snapshot, a RAG-indexed file), not just the memory note, and reindex if that
   source feeds a search index.
4. **Report in one line**: destination path + store type + why that store. No
   ceremony.
5. **Never store secret values.** If the fact involves a credential, store the
   reference (`op://...`, env var name), never the value; PII stays out of git per
   the repo's own privacy rules.
