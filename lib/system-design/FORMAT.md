# SYSTEM-DESIGN.md format

One file per repo: `docs/SYSTEM-DESIGN.md`, next to `docs/QUALITY.md`. It is the repo's system design document. Markdown prose plus fenced `uml` blocks (the notation is UML). Each block is one diagram, written as YAML. The first `# ` heading names the model. The prose between that heading and the first `## ` heading or block is the cover's intro. The prose right above a block is that diagram's note on its sheet.

High-level design is levels L1-L2, low-level design is L3-L4, both in this one file, told apart by the `level:` field.

Every block carries:

| Key | Value |
|---|---|
| `id` | stable kebab id, unique in the file; the delta keys on it |
| `type` | `usecase`, `class`, `erd`, `sequence`, `state`, `component` |
| `title` | sheet title |
| `level` | `L1` context, `L2` structure, `L3` data and flows, `L4` detail |
| `review` | optional list of questions for the reviewer, drawn as "Check here" on the sheet |
| `caption` | optional legend under the figure; replaces the per-type default (use it when a type is borrowed, such as a component sheet drawn as a process) |

## Types

| Type | Lists | Element fields |
|---|---|---|
| `usecase` | `actors`, `cases`; optional `system` (boundary label) | actor: `id`, `name`, `kind` human, system or external. case: `id`, `name`, `actor` (id or list), `with` (secondary actors, drawn on the far side), `include` [ids], `extend` (id) |
| `class` | `classes`, `relations` | class: `name`, `stereotype`, `attrs` [], `ops` []. relation: `from`, `to`, `kind` assoc, comp, realize or dep, `mult` [from, to], `label` |
| `erd` | `tables`, `rels` | table: `name`, `cols` [[name, "PK FK UQ NULL JSONB"]]. rel: `from`, `to`, `cardinality` "1:N", "1:1", "1:0..1", "0..1:0..N", `label` |
| `sequence` | `participants` [names], `messages` | message: `from`, `to`, `text`, `kind` call, return or async |
| `state` | `states`, `transitions` | state: `name`, `final`, `initial` (else the first state starts). transition: `from`, `to`, `event`, `guard` |
| `component` | `nodes`, `edges` | node: `id`, `name`, `note`, `group`, `kind` sys, ext or store. edge: `from`, `to`, `label`, `dashed` |

## Revision (front matter)

Optional YAML front matter at the very top of the file feeds the cover sheet:

```yaml
---
rev: C
decided:
  - "Hosted did:web first, did:plc as the upgrade."
  - "`authors` is the one people table."
---
```

`rev` is the review round letter, shown on the cover, the index and every title block. `decided` is the list of calls made so far, shown as "Decided in rev C".

`fz: 1.3` is read by `doc-figures render` only: it draws each figure at 1.3 times its natural size, so labels read larger. The drawing set ignores it.

## Layout hints

Every hint is optional. Sheets are a grid: `at: [col, row]` puts an element in that cell, counted from 0 at the top left. Edges run at right angles through the gutters between cells, so give every element its own cell and leave a free cell where a long edge must pass.

| Type | Hints |
|---|---|
| `component` | `lanes: [{id, name}]` at diagram level (ordered); node `lane:` (else its `group:`) picks one and the lane draws as a frame around its nodes; node `at`; edge `via` and `route` |
| `usecase` | `bands: [{name, rows: [first, last]}]` at diagram level, dashed rules between row ranges; case `at`; actor `side: left` or `right` |
| `erd` | table `at`; rel `via` and `route` |
| `state` | state `at`; transition `via` and `route` |
| `class` | class `at`; relation `via` and `route` |
| `sequence` | none: lifelines are evenly spaced, steps numbered, each label at most two lines |

- `via: [[x, y], ...]` routes an edge through grid points. A whole number is a cell center; `n.5` is the gutter after cell `n`, so `[1.5, 0]` is the gutter between columns 1 and 2, on row 0.
- `route: orth` (the default) draws right angles; `route: straight` draws one direct line.
- Without hints the renderer places elements on the grid itself: lanes become columns, otherwise columns follow edge direction (sources left), rows ordered to keep edges short. It is deterministic and never crosses a box, but a review set gets hints.
- Hints never count as a change: moving a node or rerouting an edge marks nothing in the delta.

## Tone (semantic color)

`tone` is an optional field, one of `blue`, `green`, `amber`, `rose`, `violet`, `gray`. Use it for meaning, such as one color per team or per actor, and say what each color means in the sheet note. It renders as a `tone-<name>` class: a soft fill, a stronger stroke and dark label text, in both themes. Delta colors (new, changed, removed) still win over a tone when the set is built against a base.

| Type | Takes `tone` |
|---|---|
| `component` | node; lane (`lanes: [{id, name, tone}]`, tints the frame; a node without its own tone takes its lane's); edge |
| `state` | state; transition (colors the line, arrowhead and label) |
| `usecase` | case; actor (also colors its lines to its cases) |
| `sequence` | participant, written `{name: Host, tone: blue}` (tints the head box); message |
| `class`, `erd` | relation, rel (the line, ends and label) |

- An unknown value is ignored and the sheet shows a warning.
- Tone never counts as a change in the delta.

## Identity (what the delta compares)

- An element is keyed by `id`, else `name`.
- A relation, rel, transition or edge without `id` is keyed by `from → to` plus its `kind`, `label` or `event`. Rename one of those and the delta shows a remove plus an add.
- A message is keyed by `from|to|text` plus an occurrence counter for repeats of the same triple. Inserting a message does not re-key the others; a repeat gets #2, #3 by order.
- Columns, attributes and operations are keyed by name (text before `:`, `(` or a space), so a column shows as `+col`, `-col` or `~col` inside a changed table.
- Same key, different content: `changed`. Key only in the current file: `new`. Key only in the base: `removed`.
- Layout hints (`at`, `via`, `route`, `side`, `lane`), `tone` and `review` lists are left out of the comparison.

## Prose sections

Two conventional sections are plain markdown headings, not `uml` blocks. The renderer treats them as notes. Put them after the last diagram.

| Heading | Holds |
|---|---|
| `## Cross-cutting concepts` | Rules every feature follows (arc42 section 8), one bullet each, such as idempotency keys on every write, notifications only through the outbox, money as integer cents. A spec cites a concept instead of restating it. |
| `## Risks and technical debt` | System-level risks that outlive one feature (arc42 section 11). Each bullet names the risk, the trigger that would make it bite, and the mitigation in place. |

## Example

````markdown
Quotes move to `paying` before money lands.

```uml
id: sm-quote
type: state
title: Quote states
level: L4
review:
  - Should a stuck `paying` quote expire, or wait for the webhook?
states:
  - {name: open, at: [0, 0]}
  - {name: paying, at: [1, 0]}
  - {name: paid, final: true, at: [2, 0]}
transitions:
  - {from: open, to: paying, event: start_checkout}
  - {from: paying, to: paid, event: payment_succeeded}
```
````

Full sample: `examples/marketplace/SYSTEM-DESIGN.md`.
