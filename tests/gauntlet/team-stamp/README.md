# Team stamp gauntlet

The preset that checks the team stamp: a clean-room agent with no kit opens a pull request that passes the generated checks. Engine: `commands/gauntlet.md`. Preset: custom.

| Slot | Value |
|---|---|
| Artifact under convergence | `templates/team-stamp/**` and `lib/stamp.sh` |
| Outcome contract | `card.md`; checker `check-submission.sh <repo.bundle> <submission-dir> <base-sha> [transcript]` |
| Tier 1 | `bash tests/gauntlet/team-stamp/tier1.sh` (deterministic, no network, no container, no model) |
| Clean room | `run.sh` and `Dockerfile`: a stamped scratch repo exported with `git archive HEAD`, a `gh` stand-in (`gh-shim.sh`), one credential (the probe key) |
| Probe | mid-tier model, a spend-capped key, nothing else |

Run the paid round on a host with a container runtime:

```bash
ANTHROPIC_API_KEY=<capped probe key> RUN_OUT=docs/verification/gauntlet/<date>-custom-team-stamp-scratch/round-N bash tests/gauntlet/team-stamp/run.sh
```

## The probe's work is untrusted, so the host never touches it

A model wrote into the probe's repository, its `.git/config` and its `scripts/` included. The rule: nothing a probe wrote is ever read, written, listed or executed by a host process, except six named result files.

- `run.sh` on the host makes its own directories, builds the image, creates a named volume for the probe's work, runs the probe container (the volume and the one key), then a second throwaway container, the checker, from the same image: no key, no network, the probe's volume read-only, the checker and a pristine stamp read-only from host-written directories, one fresh host-made output directory writable. It removes the volume at the end.
- `check-submission.sh` runs inside the checker container. It copies only objects, refs and HEAD out of the probe's `.git` into a repository it made, deletes the gate files from its clone and copies the pristine ones in, asserts the file lists agree, and runs the pristine `scripts/check.sh` on the probe's work as data. File lists are read NUL-delimited. A gate file the probe edited fails check 9.
- `copy-out.sh` copies out only `verdict.txt`, `checker-output.txt`, `pr.json`, `calls.jsonl`, `clean-diff.patch` and `transcript.jsonl`, each a regular file, not a symlink, at most 5 MB, with `cp -P`; the output directory itself must not be a symlink; every other entry is ignored and counted in one log line. The key scrub then scans the copies without `-I` and the run fails if the key remains.
- Limit: a hostile probe repository can forge its own verdict inside the checker container. It cannot reach the host. Read the checker output, not only the verdict.
- The container path has NOT been executed on the build host (no container runtime there): it is unverified code until the operator's first run. Tier 1 runs on the host, where every repository and file is written by the script itself, through the same checker script and `copy-out.sh`, with hostile fixtures.

## After a campaign

The operator rotates or revokes the probe key. Put this line in the run record's `ROUNDS.md`.
