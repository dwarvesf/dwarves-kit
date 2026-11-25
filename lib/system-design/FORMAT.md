# SYSTEM-DESIGN.md format

One file per repo: `docs/SYSTEM-DESIGN.md`, next to `docs/QUALITY.md`. It is the repo's system design document. Markdown prose plus fenced `uml` blocks (the notation is UML, plus C4 for structure). Each block is one diagram, written as YAML. The first `# ` heading names the model. The prose between that heading and the first `## ` heading or block is the cover's intro. The prose right above a block is that diagram's note on its sheet.

High-level design is levels L1-L2, low-level design is L3-L4, both in this one file, told apart by the `level:` field.

Every block carries:

| Key | Value |
|---|---|
| `id` | stable kebab id, unique in the file; the delta keys on it |
| `type` | `usecase`, `class`, `erd`, `sequence`, `state`, `component`, `c4` |
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
| `c4` | `elements`, `relations`; optional `boundaries`; `view` (required) | element: `id`, `name`, `c4` person, system, container, component, db, queue or node, `tech`, `desc`, `ext`, `boundary`, `zoom`. relation: `from`, `to`, `label`, `tech`, `dashed`. Details in "C4 views" below |

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
| `c4` | element `at` and `boundary`; relation `via` and `route`; `boundaries` at diagram level (see "C4 views") |
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
| `c4` | element; boundary (tints the frame; an element without its own tone takes its boundary's); relation |
| `state` | state; transition (colors the line, arrowhead and label) |
| `usecase` | case; actor (also colors its lines to its cases) |
| `sequence` | participant, written `{name: Host, tone: blue}` (tints the head box); message |
| `class`, `erd` | relation, rel (the line, ends and label) |

- An unknown value is ignored and the sheet shows a warning.
- Tone never counts as a change in the delta.

## C4 views

`type: c4` draws the C4 model for structure; UML keeps behavior and data (sequence, state, ERD). One block is one view, set by `view`: `context`, `container`, `component` or `deployment`. A zoom chain of the four views is the usual set, one sheet each.

| Field | Meaning |
|---|---|
| `elements` | `id`, `name`, `c4` kind, `tech`, `desc`, `ext`, `boundary`, `zoom`, `at`, `tone`. `c4` is `person`, `system`, `container`, `component`, `db`, `queue` or `node` (default `container`) |
| `relations` | `from`, `to`, `label`, `tech`, `dashed` (asynchronous or indirect), `via`, `route`, `tone`. Drawn as "label [tech]" |
| `boundaries` | ordered `[{id, name, kind, in, tone}]`. `kind` is `system`, `container`, `account` or `region`. `in: <boundary id>` nests one inside another. An element joins one with `boundary: <id>` |

How each kind draws:

| Kind | Shape | Type line |
|---|---|---|
| `person` | head over shoulders | `[Person]` |
| `system` | box | `[Software System]` |
| `container` | box | `[Container: tech]` |
| `component` | box | `[Component: tech]` |
| `db` | cylinder | `[Container: tech]` |
| `queue` | pipe | `[Container: tech]` |
| `node` | box with a back face | `[Deployment Node: tech]` |

- Every box shows the bold name, the type line, then `desc`. `ext: true` turns the box gray and the type line reads `[External ...]`.
- A boundary draws as a dashed frame with its name and `[kind]` at the bottom left. A frame covers its own elements and its nested frames, so a nested boundary needs its elements in columns next to the parent's. The sheet warns when a frame covers an element that is not its own.
- Without `at`, each boundary becomes a column in model order (children right after their parent). An element with no boundary sits left of the frames when it only calls into them, else right.
- `zoom: <sheet id>` makes the element a link to that sheet, marked with a small magnifier. A zoom that names no sheet draws no link and the sheet warns.
- Each sheet ends with a legend that lists only the kinds, boundaries and line styles it uses.
- Delta: elements are keyed by `id` and relations by `from → to` plus `label`, as for a component. `boundary` counts as a change (a container moving between accounts is a design change); `at`, `via`, `route`, `tone` and `zoom` do not. A new `view` on the same id marks the sheet changed.

````markdown
```uml
id: c4-containers
type: c4
view: container
title: Containers
level: L2
boundaries:
  - {id: mkt, name: Marketplace, kind: system}
elements:
  - {id: owner, name: Owner, c4: person, desc: Approves every payment., at: [0, 0]}
  - {id: core, name: Core API, c4: container, tech: "Go, REST", desc: Quotes and orders., boundary: mkt, zoom: c4-core, at: [1, 0]}
  - {id: pg, name: Postgres, c4: db, tech: Postgres, boundary: mkt, at: [2, 0]}
  - {id: stripe, name: Stripe, c4: system, ext: true, desc: Connect and Link., at: [3, 0]}
relations:
  - {from: owner, to: core, label: Approves, tech: HTTPS}
  - {from: core, to: pg, label: Reads and writes, tech: SQL}
  - {from: core, to: stripe, label: Charges, tech: REST}
```
````

Full set: `examples/marketplace-c4/` (context, container, component and deployment views, plus a base file for the delta).

## Identity (what the delta compares)

- An element is keyed by `id`, else `name`.
- A relation, rel, transition or edge without `id` is keyed by `from → to` plus its `kind`, `label` or `event`. Rename one of those and the delta shows a remove plus an add.
- A message is keyed by `from|to|text` plus an occurrence counter for repeats of the same triple. Inserting a message does not re-key the others; a repeat gets #2, #3 by order.
- Columns, attributes and operations are keyed by name (text before `:`, `(` or a space), so a column shows as `+col`, `-col` or `~col` inside a changed table.
- Same key, different content: `changed`. Key only in the current file: `new`. Key only in the base: `removed`.
- Layout hints (`at`, `via`, `route`, `side`, `lane`), `tone`, `zoom` and `review` lists are left out of the comparison.

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

Full samples: `examples/marketplace/SYSTEM-DESIGN.md` (UML) and `examples/marketplace-c4/SYSTEM-DESIGN.md` (C4).
