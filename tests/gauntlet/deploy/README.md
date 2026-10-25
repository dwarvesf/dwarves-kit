# Gauntlet campaign scheduling (phase 2, NOT installed)

Phase 1 is ssh-invoked rounds via `run-remote.sh` with `runner_host` pointing at
an always-on host; no new infra. This directory holds the phase-2 skeleton for a
scheduled campaign (one scenario row per night) and is deliberately NOT
installed anywhere: install it only when ssh-invoked runs demonstrably hurt
(the minimum-infra gate question).

- `gauntlet-campaign`, the launcher (no `.sh` extension, `#!/bin/bash`,
  BTM-friendly): picks the next un-run row from the campaign worklist, invokes
  `run-remote.sh`, appends to ROUNDS.md.
- `mini.gauntlet-campaign.plist`, LaunchAgent skeleton, `ProgramArguments[0]`
  is the launcher's own absolute path per the plist authoring rules.

Before any install: the launchd-context traps apply (verify egress + secret
cache IN launchd context, not over ssh; a cache warmed over ssh leaves a
.nostore marker that blocks the launchd retry).

- `campaign-pass [--dry-run]`, the unattended full-pass loop: ticks
  `gauntlet-campaign` through J1..J11 now, scores each row with its staged
  checker (host-side git fenced), stops on PASS-COMPLETE / a BLOCKED.md pause /
  a tick cap. Launch it detached (bg-run/tmux). Probe from `PROBE_CMD` in the
  env, else the runner's Tier-1 default; the cheap omp recipe ("Cheap probe"
  below) is an operator-exported opt-in, never baked here. This is the loop that produced
  both committed campaign records.
- `gauntlet-ab <ref-A> <ref-B> <persona> <row> <N>` (SPEC-241), an on-demand
  driver, never scheduled: runs one card against two committed artifact
  variants (rule-7 `git archive` tarballs through the runner's
  `GAUNTLET_SRC_TAR` slot), N rounds each, scored by the row's own checker, and
  writes `AB-ROUNDS.md` with a `[[AB-VERDICT ...]]` marker. A winner needs
  N >= 2 and a sweep; thinner leads report `AB-WEAK`/`AB-TIE`. Use it to pick
  between two contested revisions of an artifact; it does not revise (that is
  the gauntlet loop, run after the pick).

## Cheap probe: omp + an OpenAI-compatible endpoint

A mid-tier Anthropic probe stays the primary signal: a smarter model succeeds
despite a bad artifact (mistake 2 in `docs/guides/gauntlet.md`). A
flat-rate or cheap OpenAI-compatible model, run through `omp`
(`@oh-my-pi/pi-coding-agent`), makes a replication round close to free, so you can
run a second opinion on every round without spend anxiety. Treat a cheap-model round as a second opinion that
can confirm or strengthen a finding, never as a replacement for the mid-tier round.

Set `PROBE_CMD` in the environment (the runner reads it; unset, it uses the Tier-1
default). The block below is the `PROBE_CMD` for an OpenAI-compatible endpoint.
Replace `<endpoint-host>` and `<model-id>` with your provider's values.

```bash
command -v omp >/dev/null && echo omp-baked > /work/omp-install.log || {
  export PATH="$HOME/omptool/node_modules/.bin:$PATH"
  npm install --no-fund --no-audit --prefix "$HOME/omptool" @oh-my-pi/pi-coding-agent bun \
    > /work/omp-install.log 2>&1 || { echo omp-install-failed; cat /work/omp-install.log; exit 0; }
}
mkdir -p "$HOME/.omp/agent"
printf 'providers:\n  cheap:\n    baseUrl: https://<endpoint-host>/v1\n    api: openai-completions\n    apiKey: %s\n    models:\n      - id: <model-id>\n' \
  "$ANTHROPIC_API_KEY" > "$HOME/.omp/agent/models.yml"
printf 'tools:\n  approvalMode: yolo\n  enabled: true\nsetupVersion: 2\nmodelRoles:\n  default: cheap/<model-id>\n' \
  > "$HOME/.omp/agent/config.yml"
timeout 1800 omp -p --auto-approve --mode json --model cheap/<model-id> \
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

The shape stays the same for any OpenAI-compatible endpoint. The `command -v omp`
guard uses the baked toolchain (`tests/gauntlet/cleanroom/Dockerfile`) when present and
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
   provider it actually authenticates; put the endpoint's key there. The config file that holds it lives under the container-only HOME and dies
   with the room, BUT anything the probe or its tools ECHO into `/work` (transcripts,
   stderr, install logs) is persisted, on failing rounds too. run.sh redacts every
   literal occurrence of the key before persisting and refuses the persist if
   redaction cannot clean it; treat that as a backstop, not a license, the record
   still gets an eyeball before commit (rule 8 in `commands/gauntlet.md`).

Launch long rounds detached (tmux or any background runner) so a closed terminal
does not kill them. Watch a round live: `bash tests/gauntlet/cleanroom/watch.sh`.
