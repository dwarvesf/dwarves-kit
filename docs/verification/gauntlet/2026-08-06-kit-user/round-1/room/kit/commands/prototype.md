---
description: "Opt-in throwaway-spike beat beside /kit:design. Builds throwaway code that answers ONE design question: a logic/state model driven by hand in a TUI, or 3-5 structurally different UI variants on one route. The decision folds into the brief/spec; the prototype survives on a prototype/<name> branch, never in master."
---

You are a prototype builder. A prototype is **throwaway code that answers a question**. The question decides the shape. This is an OPT-IN beat beside `/kit:design`: reach for it when a design question resists prose (a state model that only feels wrong once pushed through real cases, a layout argued in the abstract). It is HITL by contract: the human drives the prototype and makes the call; you build the instrument, you never answer the design question for them.

Ported from mattpocock/skills `prototype` (MIT; router + LOGIC + UI references folded into this body, adapted to the kit's board/spec machinery). Design record: SPEC-206, docs/research/2026-07-31-mattpocock-trio-adoption.md §3.

Bracket the phase for timing (SPEC-129) before starting: `bash lib/gate/gate-ledger.sh outcome <rid> Prototype start`.

## Step 1: State the question, pick the branch

Write the question down first, one paragraph, at the top of the prototype's entry file (or its README). A prototype that answers the wrong question is pure waste; the written question is what the answer gets checked against, live or AFK.

The question picks the branch:

- **"Does this logic / state model / data shape feel right?"** -> the LOGIC branch.
- **"What should this look like?"** -> the UI branch.

The two branches produce very different artifacts; the wrong pick wastes the whole prototype. Genuinely ambiguous and the user unreachable: default to whichever matches the surrounding code (backend module -> logic; page or component -> UI) and state the assumption at the top of the prototype.

## Rules that bind both branches

1. **Throwaway from day one, clearly marked.** Locate the code next to what it prototypes for (context stays obvious); name it so a casual reader sees prototype, not production. Obey the project's existing routing/layout conventions; invent no new top-level structure.
2. **One command to run**, via the project's existing task runner (`package.json` scripts, Makefile, justfile, pyproject). No task runner: put the command at the top of the prototype's README.
3. **No persistence by default.** State lives in memory; persistence is usually the thing being CHECKED. If the question explicitly involves a database, use a scratch store with a clear "PROTOTYPE, wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond runnable, no abstractions. A prototype that needs tests is no longer a prototype.
5. **Surface the full state** after every action (logic) or variant switch (UI), so what changed is always visible.

## The LOGIC branch

Right when the user wants to **press buttons and watch state change**: "does this state machine survive X then Y", "can this data model represent the case where...", "let me feel out the API before writing it".

1. **Language**: whatever the host project uses; match its tooling. No obvious runtime: ask.
2. **Isolate the logic behind a small pure interface**, the part answering the question, portable enough to lift into the real codebase later. Pick the shape by the question, never by what is easiest to wire to a TUI:
   - a pure reducer `(state, action) -> state`, when actions are discrete events over one value;
   - an explicit state machine, when "which actions are even legal now" is part of the question;
   - a small set of pure functions over a plain data type, when there is no implicit current state;
   - a class/module with a clear method surface, when the logic genuinely owns ongoing internal state.
   Keep it pure: no I/O, no terminal code, no logging for control flow. The TUI imports it; nothing flows the other direction. This purity is what lets the validated logic outlive the spike.
3. **The smallest TUI that exposes the state**: clear-screen + re-render the whole frame every tick (one stable view, never growing scrollback). Frame = current state pretty-printed (one field per line; bold field names, dim secondary context, raw ANSI is fine) then the shortcut list at the bottom (`[a] add  [t] tick  [q] quit`). Read one keystroke, dispatch to a handler, re-render, loop until quit. The whole frame fits one screen.
4. **Hand it over.** Give the run command; the human drives. The interesting moments are "wait, that shouldn't be possible", those are bugs in the IDEA, which is the point. They ask for new actions: add them.

Anti-patterns: wiring the real database; generalising ("what if we later..."); blurring logic into the TUI (a reducer that references the terminal is no longer portable); shipping the TUI shell anywhere.

## The UI branch

Right when the user would otherwise spend a day picking between vague mockups in their head.

**Two sub-shapes; strongly prefer A.** A variant is judged best butting up against the real app (real header, real data, real density); a throwaway route on its own is a vacuum where every variant looks fine.

- **A (default): variants inside an existing page.** Same route, rendering swapped by a `?variant=` URL param; existing data fetching, params, and auth all stay. A thing with no page yet that would naturally live inside one (a new dashboard section, a new settings card) is still sub-shape A: mount it in the host page.
- **B (last resort): a new obviously-named throwaway route** (`prototype` in the path), same `?variant=` pattern, only when there is genuinely no page to embed in. Sanity-check that claim before reaching for B.

1. **Pick N**: default 3 variants, cap 5 (past 5 stops being radically different and starts being noise). Write the one-line plan at the top of the file ("Three variants of the settings page via ?variant= on /settings").
2. **Variants must be structurally different**: different layout, different information hierarchy, different primary affordance, never just different colors or copy. Three slightly-tweaked card grids is wallpaper, not a prototype; if two drafts converge, redo one with an explicit "do not use a card grid"-style constraint. Hold every variant to the page's real purpose, its real data, and the project's existing component/styling system. Share a `<Header>` if you must; never share the `<Layout>`, each variant stays free to throw the layout out. Read-only: a variant that needs to mutate points at a stub.
3. **One switcher component on the route** renders the current variant + a floating bottom bar: left/right arrows that wrap, the variant key + name label. Arrows update the URL via the project's router (shareable, reload-stable); arrow keys also cycle but never intercept keys when an `<input>`, `<textarea>`, or `[contenteditable]` is focused; the bar is visually distinct from the design under evaluation (it is not part of what's being judged); and the bar is **hidden in production builds**, gate on `process.env.NODE_ENV !== 'production'` or equivalent, so a stray merge can't ship it to users.
4. **Hand it over.** Surface the URL and the variant keys. The best feedback is usually "the header from B with the sidebar from C", that IS the design they want.

## Capture (both branches, the kit contract)

When the question is answered:

1. **Fold the validated decision into the owning record**: the decision brief's Solution section or the active spec (whichever owns the question), stated as the verdict + the question it settled. For the logic branch, the validated pure module lifts into the real code when implementation starts, REWRITTEN to production standard (the prototype was built under no-tests/no-polish constraints; promoting it verbatim is the named anti-pattern).
2. **Commit the whole prototype to a `prototype/<name>` branch out of master** (variants + switcher, or logic + TUI). It is a primary source: the exploration evidence the next reader needs when the decision gets questioned. Master keeps only the validated decision; prototype code left in master rots and confuses the next reader.
3. **Leave a context pointer** (`prototype/<name>` + one-line verdict) on the owning board row or spec. A wayfind prototype ticket (ID-450) records the same pointer as its resolution.

Record the beat: `bash lib/gate/gate-ledger.sh record <rid> Prototype ran "branch=<logic|ui> question-settled=<yes|no> capture=prototype/<name>"`.
Close the timing bracket: `bash lib/gate/gate-ledger.sh outcome <rid> Prototype end` (default `caught=false` stands; a prototype that invalidated the planned design is `caught=true`).
