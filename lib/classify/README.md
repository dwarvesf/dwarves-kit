# classify

Deterministic classifiers that turn a one-line task description into a lane, a specialist role, a significance verdict or a work type. Pure bash and grep, no model call, so the same input gives the same answer. They suggest and never block.

**Entry points**
- `bin/classify <verb> ...` forwards to `lib/classify/classify.sh`, which dispatches each verb to the script that owns it.
- `lib/classify/lane-classify.sh classify|explain|check|risk|escalate|floor|deescalate|lanes|flags`: pick the risk lane (`tiny`, `normal`, `full`, `bug`, `backfill`). `floor <root> [<base>]` returns `full` when the diff hits a hard path.
- `lib/classify/role-classify.sh classify|explain|domains|agent-for`: map a task to a specialist domain. `agent-for <domain>` names the builder subagent.
- `lib/classify/task-type-classify.sh classify|types`: map a task to a work type, which sets the shape of the proof of done.
- `lib/classify/significance-classify.sh classify|explain|record|signals`: say whether a change earns the understanding tap, wave or not-significant. `record <rid>` writes the debt marker through the gate ledger.
- `lib/classify/route-suggest.sh <ledger.tsv> <task>`: suggest the cheapest model tier that passed at parity. It abstains (exit 2) when the ablation data is too thin.

**Tests**: `lib/classify/` has no `tests/` directory. The suites are `tests/test-lane-classify.sh`, `tests/test-lane-deescalate.sh`, `tests/test-lane-escalation.sh`, `tests/test-role-classify.sh`, `tests/test-significance-classify.sh` and `tests/test-classify-md-inert.sh`. `route-suggest.sh` is covered by `tests/test-model-routing.sh` and `tests/test-routing.sh`. No suite is named for `task-type-classify.sh`. `tests/test-hooks.sh` and `tests/test-meta-vmodel-dispatch.sh` call it. Run one with `bash tests/run-all.sh --only lane-classify`.

**Spec and docs**: `docs/specs/SPEC-050-lane-classify-flags.md` for the flag model, `docs/specs/SPEC-123-significance-classify.md`, and `docs/verification/task-types.md` for the type registry.
