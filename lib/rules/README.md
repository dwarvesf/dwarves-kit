# rules

The kit's implicit state machines and decisions, written as [gdp-wired](https://www.npmjs.com/package/gdp-wired) rules with the laws the docs promise about them, proven, and held to the bash that runs them.

Every gate, ledger, queue and hook in the kit is a small state machine: a run's fix cycles, a goal's claim, a lane's effective value, a hook's allow/block. Until now their promises ("at most two fix cycles", "never push to main", "a quarantined slug is never launched") lived in prose and in example tests. Here each one is a rule, each promise is a law over every run of it, and a kernel checks the proof.

**What is in it**
- `verify-loop.ts`: the verification pipeline's retry loop, the one rule the kit runs directly. `bin/verify-loop` steps the compiled rule and `/kit:execute` does what it prints, so nothing counts retries by hand.
- `gates/`, `goals/`, `specs/`, `wrap/`, `hooks/`: one folder per area. Each has one `<name>.ts` per rule (the rule, its laws, its kept broken variants), one `<name>.bridge.ts` per rule backed by runnable bash, an `index.ts` listing `RULES`, a `prove.ts`, and `FINDINGS.md`.
- `FINDINGS.md` in each area: every rule with its source, its laws and its bridge agreement; every promise the code broke, with the counterexample and the fix; every promise the code knowingly does not keep; every machine found but not modelled, and why.

**How each rule is held to the code**
- The rule follows what the bash does, cited by file and function, not what the docs say.
- Laws over state reloaded from disk are proven from any state (`{from: 'any'}`), and a proof counts only when `proven && checked && !assumes`.
- Next to each rule sits at least one broken variant, the bug its key law rules out, and the prover asserts it is refused. A variant named `pre-fix` or marked *as found* is the bash as it was before this module found and fixed it.
- A bridge runs the real script in a temp sandbox (temp HOME, repos and ledgers; `claude`, `gh`, `tmux` and the network stubbed through the scripts' own seams) on enumerated and seeded inputs, and compares what the bash decides or stores with the rule. A divergence is either a modelling error or a bug in the bash.

**Running it**
- `node lib/rules/prove.ts`: every law proven, every variant refused, every recorded finding still refuted (about a minute). `tests/test-rules.sh` runs this and the `bin/verify-loop` behavior checks.
- `node lib/rules/prove.ts --bridges`: also every bridge, several thousand real script runs. Run it on a box, not a laptop.
- `node lib/rules/<area>/prove.ts [--no-bridges] [--only <rule>]`: one area.

**Install**: `install.sh` runs `npm ci` here (gdp-wired is pinned in `package-lock.json`). Hooks stay bash and never load these files; only `bin/verify-loop` and the provers need Node 22+.

**Adding a rule**: write it from the code, state the promised laws, keep the bug as a variant, write the bridge, add it to the area's `RULES`, and run the area's prover until every law is proven and every bridge agrees. If a promised law is refuted and the bridge reproduces it on the real bash, that is a bug: fix the bash, keep the old behavior as a variant, and add a regression test to the suite that covers the script.

**Spec and docs**: `docs/specs/SPEC-431-gdp-wired-rules.md`, `docs/verification/gdp-wired-proof.md`.
