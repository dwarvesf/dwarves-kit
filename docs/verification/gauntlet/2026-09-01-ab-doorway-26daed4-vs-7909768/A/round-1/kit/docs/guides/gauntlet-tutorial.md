# Gauntlet tutorial: from nothing to a run

`docs/guides/gauntlet.md` tells you what the pieces are. This file shows you, step by
step, what to type and which files to create. Two paths: A runs the instance that
already exists (zero prep); B builds a custom run from scratch, with every slot file
written out so you can copy and adapt.

## The 60-second model

```
 you fix the OUTCOME ──▶ a fresh probe agent tries it, unaided, in a clean room
                              │ fails? the findings tell you what the ARTIFACT lacks
                              ▼
                         the artifact gets revised ──▶ new room, new probe, again
                              │ (max 3 rounds)
                              ▼
                         a probe passes unaided ──▶ the artifact is proven
```

You never fix the probe. You never help the probe. The artifact is the patient; the
probe is the thermometer.

Four things configure a run (the "slots"). Everything else is engine and does not
change:

| Slot | Plain meaning | What you actually create |
|---|---|---|
| Artifact | the files being improved | nothing new, just a glob list |
| Outcome contract | how we know the probe succeeded | 3 files: a card, a checker script, a Tier-1 script |
| Probe framing | who the probe pretends to be | one sentence |
| Clean-room recipe | how a fresh sandbox is built | 1 script (+ Dockerfile), or reuse an existing one |

## Path A: run the one that exists (10 minutes of prep, zero building)

The kit ships one complete instance: the kit's own onboarding surface
(`tests/gauntlet/`). Use it to see a full run before building your own.

1. `cd` the dwarves-kit checkout, clean tree, on master.
2. Confirm the probe key resolves: `kit.toml [gauntlet]` names `probe_key_ref` (a 1P
   ref for a spend-capped Anthropic key) and `runner_host`. That key is the ONLY
   credential the room gets.
3. Say: **`/kit:gauntlet onboarding`**.
4. The kit shows the inputs table filled from `tests/gauntlet/README.md` (persona A,
   the kit USER). You confirm it. That is the whole interface: confirm or override
   rows.
5. Watch nothing. Each round is a container build plus one probe session; the record
   lands in `docs/verification/gauntlet/<date>-onboarding-<slug>/`. Read `ROUNDS.md`
   when it stops.

## Path B: build your own run (the real tutorial)

Worked example, chosen because it needs NO host access and no new infrastructure: a
**spec-completeness gauntlet**. Artifact = one spec you wrote. Outcome = a cold probe
implements it in a fixture repo without hitting a question the spec cannot answer.
The same five steps apply to any artifact; a runbook or API surface only changes the
file contents, not the steps.

### Step 1: name the artifact (30 seconds)

The globs the reviser may edit. For our example:

```
docs/specs/SPEC-101-rate-limiter.md
```

One file is fine. For a runbook it would be `tools/<x>/deploy/**/<x>-runbook.md`;
for onboarding it is the CONTRIBUTING/README/scripts set.

### Step 2: write the card (10 minutes, this is the important one)

The card is the task the probe attempts. It is a goal contract: outcome, acceptance
criteria, a verification command, and a stop-on-blocker clause. Small: one agent-day
max. Create `gauntlet/card.md` anywhere outside the artifact globs:

```markdown
# Card: implement SPEC-101 in the fixture repo

You have a fixture repo at /work/fixture and a spec at /work/spec.md.
Implement the spec exactly. Do not guess: if the spec does not answer a
question you need answered, write it to /work/OPEN-QUESTIONS.md and stop.

Acceptance:
- `npm test` green in /work/fixture (the spec's own Verification section)
- no entry in /work/OPEN-QUESTIONS.md
Verification command: `cd /work/fixture && npm test`
```

The trick that makes this a SPEC gauntlet: an unanswerable question is the failure
signal. For a runbook card it would be "restore the service; every command must come
from the runbook, log any step where the runbook was wrong or silent".

### Step 3: derive the checker (10 minutes)

A script that says PASS/FAIL on what the probe left behind, derived from the card's
verification command. Create `gauntlet/check.sh`:

```bash
#!/bin/bash
# PASS iff the card's verification passes AND the probe logged no open questions.
set -e
work="$1"
cd "$work/fixture" && npm test || { echo "FAIL: tests red"; exit 1; }
[ -s "$work/OPEN-QUESTIONS.md" ] && { echo "FAIL: spec left questions"; exit 1; }
echo PASS
```

No checker yet? The command derives one for you at the confirm step, from the card's
verification line. Write your own when you want extra assertions.

### Step 4: write Tier 1 (10 minutes, saves you money every round)

Cheap mechanical checks that run BEFORE any paid probe. Every red here is a free
finding. Create `gauntlet/tier1.sh`:

```bash
#!/bin/bash
# Free checks: artifact exists, has the load-bearing sections, commands parse.
set -e
spec="docs/specs/SPEC-101-rate-limiter.md"
[ -f "$spec" ] || { echo "FAIL: spec missing"; exit 1; }
for h in "## Verification" "## Acceptance" "## Task Breakdown"; do
  grep -qF "$h" "$spec" || { echo "FAIL: $h section missing"; exit 1; }
done
echo PASS
```

Rule 10 grows this file: any probe finding reducible to a grep moves here, and the
next round gets cheaper.

### Step 5: the clean room (15 minutes, mostly copying)

A script that builds a fresh sandbox from COMMITTED state, puts ONLY the artifact +
card + probe key inside, and runs the probe. Copy
`tests/gauntlet/cleanroom/run.sh` + `Dockerfile` as your starting point and gut the
onboarding parts; the shape that must survive:

```bash
# 1. stage committed state (uncommitted fixes do not exist for the probe)
git archive HEAD | tar -x -C "$STAGE"
# 2. strip the answer key: your checker, tier1, prior run records, the gauntlet's own docs
rm -rf "$STAGE/gauntlet" "$STAGE/docs/verification/gauntlet"
# 3. inject exactly: artifact, card, fixture skeleton, ONE spend-capped API key
# 4. run the probe with the framing line, capped session
# 5. copy the transcript + outputs OUT, tear the room DOWN
```

Artifact-kind cheat sheet:

- **Repo/doc artifact** (spec, docs, onboarding): container + `git archive`. Use it.
- **Host artifact** (a runbook against a real machine): a credential-stripped
  clone/VM snapshot; the kit rejects a snapshot holding any credential beyond the
  probe key, and asks you to confirm the destructive teardown before round 1. Do
  your first-ever run with a container kind; graduate to host kind later.

### Step 6: run it

Say: **`/kit:gauntlet`** and answer the preset question with "custom", or hand it
everything in one line:

> run the gauntlet: artifact docs/specs/SPEC-101-rate-limiter.md, card
> gauntlet/card.md, checker gauntlet/check.sh, tier1 gauntlet/tier1.sh, clean room
> gauntlet/run.sh, probe framing "you are a contractor with no prior context
> implementing this spec", cap 3

The command validates every input against its bad-input table BEFORE spending
anything. Missing or vague inputs get a three-beat reply: what is wrong, why it
matters, the concrete fix (often "want me to scaffold it?"). **Three or more inputs
missing is a designed good outcome**: you get the build checklist in dependency
order, for free, and no round runs.

### Step 7: read the result

Everything is in `docs/verification/gauntlet/<date>-custom-<slug>/ROUNDS.md`:

| You see | It means | You do |
|---|---|---|
| SOLID | two consecutive unaided passes | the artifact is proven; watch the first real consumer anyway |
| REVISE | improving, cap hit | apply the open findings by hand, rerun later |
| RECONSIDER | not converging | the gap list names a STRUCTURAL hole (a missing tool or section, not wording); decide, then rerun |

Per round: `findings.md` (each finding carries a transcript quote), `transcript.md`
(the probe's full session), `submission/`, `artifact-diff.patch` (what the reviser
changed after that round).

## Cheap probe: omp + an OpenAI-compatible endpoint

A mid-tier Anthropic probe stays the primary signal (see mistake 2 below). A
flat-rate or cheap OpenAI-compatible model, run through `omp`
(`@oh-my-pi/pi-coding-agent`), makes a replication round close to free, so you can
run a second opinion on every round without spend anxiety. Proven 2026-08-31: a
NeuralWatt `deepseek-v4-flash` round reproduced every finding from the same-day
sonnet round, one finding strengthened (`docs/verification/gauntlet/2026-08-31-user-J1-nw/ROUNDS.md`).

`PROBE_CMD` for the omp/NeuralWatt recipe:

```bash
command -v omp >/dev/null && echo omp-baked > /work/omp-install.log || {
  export PATH="$HOME/omptool/node_modules/.bin:$PATH"
  npm install --no-fund --no-audit --prefix "$HOME/omptool" @oh-my-pi/pi-coding-agent bun \
    > /work/omp-install.log 2>&1 || { echo omp-install-failed; cat /work/omp-install.log; exit 0; }
}
mkdir -p "$HOME/.omp/agent"
printf 'providers:\n  neuralwatt:\n    baseUrl: https://api.neuralwatt.com/v1\n    api: openai-completions\n    apiKey: %s\n    models:\n      - id: deepseek-v4-flash\n' \
  "$ANTHROPIC_API_KEY" > "$HOME/.omp/agent/models.yml"
printf 'tools:\n  approvalMode: yolo\n  enabled: true\nsetupVersion: 2\nmodelRoles:\n  default: neuralwatt/deepseek-v4-flash\n' \
  > "$HOME/.omp/agent/config.yml"
timeout 1800 omp -p --auto-approve --mode json --model neuralwatt/deepseek-v4-flash \
  "$(cat /work/PROMPT.txt)" </dev/null > /work/transcript.jsonl 2>/work/probe-stderr.log
rc=$?; echo probe-exit=$rc

# Optional: persist the probe's OWN session logs (fuller fidelity than the
# --mode json stdout projection above), text files only. `models.yml` carries
# the room's one credential and must never leave the container; copy known
# text extensions one file at a time and delete anything binary rather than
# risk it dodging the (text-only, grep -I) scrub below.
mkdir -p /work/omp-state
find "$HOME/.omp" -type f \( -name '*.log' -o -name '*.jsonl' \) ! -name 'models.yml' ! -name 'config.yml' \
  -print0 2>/dev/null | while IFS= read -r -d '' f; do
    if file -b --mime-encoding "$f" 2>/dev/null | grep -q binary; then continue; fi
    cp "$f" "/work/omp-state/$(basename "$f")"
  done

exit $rc
```

Swap `neuralwatt`/`deepseek-v4-flash`/`baseUrl` for any other OpenAI-compatible
endpoint; the shape stays the same. The `command -v omp` guard uses the baked
toolchain (`tests/gauntlet/cleanroom/Dockerfile`, SPEC-238) when present and
writes the `omp-baked` signal; on an unbaked image it falls back to the
per-round install unchanged, so this block still runs to completion either
way.

Three rules this recipe cost real rounds to learn:

1. `run.sh` writes `PROBE_CMD` through an unquoted heredoc. Text that arrives FROM a
   variable expansion is not re-scanned for escapes. Set `PROBE_CMD` in the launcher
   carrying plain `$VAR` / `$(...)`, never `\$VAR` (a backslash-escaped dollar survives
   into the room literally and never resolves). Since the block above itself contains
   single quotes, assign it via a quoted heredoc, not a single-quoted string:
   `read -r -d '' PROBE_CMD <<'EOF' ... EOF`. run.sh already writes the room preamble
   (probe HOME, git identity, `cd /work`); the block starts after that.
2. `omp` blocks forever on a non-TTY stdin. Always redirect `</dev/null`, or the round
   hangs until the timeout.
3. The room has exactly one credential slot, `ANTHROPIC_API_KEY`, regardless of which
   provider it actually authenticates; put the NeuralWatt (or other endpoint) key
   there. The config file that holds it lives under the container-only HOME and dies
   with the room, BUT anything the probe or its tools ECHO into `/work` (transcripts,
   stderr, install logs) is persisted, on failing rounds too. run.sh redacts every
   literal occurrence of the key before persisting and refuses the persist if
   redaction cannot clean it; treat that as a backstop, not a license, the record
   still gets an eyeball before commit (rule 8).

`bg-run` (ops-toolkit) is a convenient launcher for the round itself (tmux session +
a status dir); it is an operator convenience, not a kit dependency.

Watching a round live: `bash tests/gauntlet/cleanroom/watch.sh`.

## The three mistakes everyone makes first

1. **Helping the probe.** One answered question voids the round and destroys the
   finding you paid for. Let it drown; the drowning is the data.
2. **A frontier probe.** A smarter model succeeds despite the bad artifact. Mid-tier
   is load-bearing, not a cost saving.
3. **An oversized card.** "Implement the whole feature" conflates "artifact failed"
   with "task too hard". One bounded slice; park the rest.

## Prep-cost summary

| Path | Prep | Per round |
|---|---|---|
| A: onboarding preset | confirm the key, ~10 min | container build + 1 probe session |
| B: custom, container kind | ~45 min (card + checker + tier1 + room) | same |
| B: custom, host kind | above + a stripped snapshot/restore recipe | snapshot restore + 1 probe session |
