---
name: system-design
description: Own the repo's system design document at docs/SYSTEM-DESIGN.md: its format, its updates per feature, and rendering it as a UML drawing set (HTML sheets) with the delta against a base git ref marked new / changed / removed, published as an Artifact for design review. Triggers "system design", "update the architecture doc", "HLD", "LLD", "render the UML", "show the design as UML", "update the UML for this feature", "uml drawing set", "review this design in UML". NOT for one-off hand-drawn figures or standalone concept diagrams.
disable-model-invocation: false
---

# system-design

A repo keeps ONE system design document: `docs/SYSTEM-DESIGN.md`. High-level design is levels L1-L2, low-level design is L3-L4, in the same file, told apart by the `level:` field. This skill owns the document's lifecycle: its format, its per-feature updates, and rendering the UML drawing set (a self-contained HTML page that marks what a branch changed). A human reviews a feature's design as UML, sheet by sheet.

The engine ships with the kit in `~/.claude/dwarves-kit/lib/system-design/`: `FORMAT.md` (the model format, read it before editing a model), `build`, `shots.mjs`, `template.html`, `delta.js`, `layout.js`, `test.mjs`, `examples/marketplace/` (no hints, the fallback layout). This file holds the workflow only.

## Where a design lives

- A cross-repo platform design lives in the platform repo's `docs/SYSTEM-DESIGN.md`. A code repo's own model holds only its internal L3-L4 detail.
- One sheet per concern: L1 use cases; L2 one component sheet per pipeline; L3 one ERD per store and one sequence per flow; L4 one state machine per entity with a lifecycle.
- Commit the rendered set next to the model at `docs/design/<feature>-uml.html`, rebuilt from the same model each round.

## During design (a feature touches the model)

1. Read `~/.claude/dwarves-kit/lib/system-design/FORMAT.md`. Open `docs/SYSTEM-DESIGN.md`; create it on first use with a `# <Model name>` heading.
2. Edit it as a delta. Touch only the diagrams the feature changes. Add a new diagram only when no existing one can hold the change. Start at L1 and go down to L4 only where the risk sits (money, state, concurrency, data shape). Keep ids stable: a renamed id reads as remove plus add.
3. Put one or two sentences of prose above each touched block: what changed and why.
   When the feature adds a cross-cutting rule or a system-level risk, update the `## Cross-cutting concepts` and `## Risks and technical debt` sections too (see the engine's `FORMAT.md`).
   Add a `review:` list to each touched block: the one or two calls the reviewer must make on that sheet.
4. Lay every touched sheet out by hand with hints (`FORMAT.md`, Layout hints): `at` per element, `lanes` per repo or stage, `bands` for use cases. Sketch the grid first (which column is which repo or stage, which row is which tier), then place. Never publish raw auto-layout for a review; the fallback only keeps an unhinted sheet readable.
5. Build against the branch's merge-base:

   ```bash
   base=$(git merge-base HEAD origin/main)
   ~/.claude/dwarves-kit/lib/system-design/build --model docs/SYSTEM-DESIGN.md --base "$base" --out <scratchpad>/uml-<repo>.html
   ```

   `--shots <dir>` also writes one PNG per sheet (`<sheet-id>.png`, plus `cover.png`; headless Chrome and node via `shots.mjs`; `CHROME` env overrides the macOS path). `SHOT_SCALE=2` writes them at 2x for docs and Notion, and `SHOT_CLIP=figure` crops each PNG to the diagram alone (no title block or prose), `--sheets a,b` limits it.
   The build exits non-zero if a PNG is 10 KB or smaller or two PNGs share an md5.

   `--style <fragment.html>` adds a repo's own look: an HTML fragment (a Google Fonts `<link>` plus a `<style>` that redefines `--display`, `--body`, `--mono` or color tokens, or `--fz` to scale every diagram label (box sizes follow)) inserted after the template's styles, so it wins. Keep the fragment in the repo, such as `docs/system-design-style.html`.

   No git history to diff (a scratch file, an example): `--base-file <old SYSTEM-DESIGN.md>`. Omit both for a plain drawing set.
   Optional `tone: blue|green|amber|rose|violet|gray` on nodes, lanes, states, cases, actors, participants and edges colors a sheet by meaning (`FORMAT.md`, Tone); it never counts as a change.
   Look at every PNG before publishing: no label on a box or another label, no edge through a box, lanes and rows aligned. Move cells with `at` or add a `via` until it holds.
6. Publish the HTML with the Artifact tool. The `<title>` is the model name. Rebuild to the SAME file path every time, so the Artifact URL stays.
7. Ask the human to review per changed diagram: list each sheet with a `changed` or `new` tag and its "Check here" questions, and wait for their call before code starts.

## Review rounds

- Each review round gets the next revision letter in the front matter `rev:` (A, B, C).
- Each call the reviewer makes goes into the front matter `decided:` list, which the cover shows; then it goes into the spec amendment.
- Build each round against the previous round's commit, so the delta shows only what this round changed.

## Notes

- The page parses and draws in the browser (js-yaml 4.1.0 from cdnjs, pinned with SRI; `layout.js` is the grid layout and router, inlined). Text is measured with the page's fonts, so boxes fit their labels. Model errors show on an "Errors" sheet; layout warnings (a clashing `at`, a label with no clear spot) show on their sheet; the build never parses YAML.
- The build refuses a model containing `</script` or a build placeholder.
- Change `delta.js`, `layout.js` or the fixture: run `node ~/.claude/dwarves-kit/lib/system-design/test.mjs` (needs node and network for js-yaml). It checks the delta, hint parsing, and that the fallback layout of every marketplace sheet is deterministic with no edge through a box.
