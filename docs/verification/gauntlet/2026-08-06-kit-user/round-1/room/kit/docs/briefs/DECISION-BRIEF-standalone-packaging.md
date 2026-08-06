# Decision Brief: standalone-first packaging (module = standalone tool + thin kit adapter)

Date: 2026-07-25 · Source: operator direction ("each part stands alone so people can contribute
and improve it; together they become the framework") + the packaging prior-art refresh. Status:
DRAFT (feeds the ID-396 ADR; ID-395 visual proof is the pilot extraction). Consuming rows:
ID-396, ID-395. Survey: `docs/research/2026-07-25-packaging-prior-art-refresh.md`.

## Verified current state

- ID-277 kit-modularity (shipped 2026-07-05) made modules separable INSIDE the kit: standalone
  `<subsystem> <verb>` commands, layered install, `kit.toml [modules]` as an install record,
  12-module registry, plain-file artifacts (ledger/board/specs).
- The delete-the-kit test FAILS today: no module works with the kit uninstalled; no per-host
  adapters are generated; visual proof + test-design live as external skills or embedded docs.

## The design (from the survey's recommendation, PICKUP 1-5)

Each capability ships as:

1. **Plain git-trackable files as the primary artifact** (markdown/jsonl/csv; OpenSpec model). The
   file IS the source of truth; any tool can `cat` it; another tool reads it without an API.
2. **One script/binary that reads+writes those files with ZERO kit present.** That pair is the
   whole tool, fully useful alone.
3. **ONE generated per-host adapter** from the same core (a SKILL.md for Claude Code, a bare CLI
   entry; MCP wrapper only if genuinely useful). Never hand-maintained per-harness copies
   (mattpocock's `agents/openai.yaml` sibling-file pattern is the live example).
4. **The kit owns ONLY the composition layer**: `kit.toml [modules]` entries declare what a module
   EXPOSES (commands, hooks, ledger paths) into the shared registry (Taskmaster-style surface
   scoping); spec-kit's non-destructive override stack (module-local > project > kit-default)
   resolves conflicts and reverts cleanly on uninstall.
5. **agent-os v3 "defer, don't own" cut per module**: each module keeps only its irreducible value
   (proof-capture captures and hands back a path; it does not own verification-flow orchestration).

## Practice-level additions (acpx-arc session, same day; mirrors the ID-396 row annotation)

The ADR ships these as mechanics, not prose:

1. **Contract block in every module README**: IN (argv/stdin) / OUT (artifact file + schema) /
   EXIT (code semantics). The rule stated verbatim: "a module's API is its artifact schema, not
   its shell functions"; consumers read the artifact, never source the script.
2. **Thin-adapter rule made explicit**: kit integration = one command shim + the manifest EXPOSES
   row, ZERO logic in the shim; logic accumulating in an adapter is the coupling smell.
3. **The acceptance test mechanized as two spec-template ACs** for every future module spec:
   "works with the kit deleted (standalone invocation documented)" + "kit degrades to one missing
   capability with the module deleted". So the delete test fires per-module forever, not once in
   the ADR.
4. **Enforcement rides ID-397**: spec-validate gains the advisory lens question "what is this
   module's standalone contract; does it pass the delete test?".

## Acceptance test (the doctrine in one line)

Delete the kit -> every tool still fully works (lost convenience, never capability). Delete any one
tool -> the kit is missing one capability, never broken.

## AVOID (from the survey)

Ruflo theater-surface (command list outrunning wired capability); BMAD core-coupled packs (a format
that only makes sense with the orchestrator running); superpowers per-harness reinstall;
registry-less implicit discovery; an installer that silently wires telemetry or settings
(az-skills skill-feedback caution).

## North-star conformance (§6)

N4 is this brief's criterion verbatim; serves N7 (a contributor can improve one tool without
learning the kit). Extends, never re-opens, ID-277's shipped decisions.

## Exit criteria

1. ID-395 (visual proof) passes the acceptance test as the pilot: usable by a developer with no
   kit installed, AND auto-invoked by the proof contract when the kit is present.
2. A second module (test-design methodology) extracted on the same pattern with no new doctrine
   decisions needed (the ADR was sufficient).
3. A `[modules]` exposure declaration exists for both, and uninstalling either leaves the kit
   suite green.
