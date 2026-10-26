# Implementation notes: gauntlet corpus out of the tree

Only decisions, deviations, tradeoffs and open questions.

| # | Note |
|---|---|
| 1 | Cut: every tracked `transcript.jsonl` (35) and `fixture-repo.tar.gz` (5, all under 60 KB, moved by name as directed), 40 files, 78,173,886 bytes. No other tracked file in the gauntlet dir is over 200 KB; the largest left is a 22 KB patch. The dir went from 76 MB to 1.1 MB. |
| 2 | Asset: one `tar.gz` built with `gtar --sort=name`, fixed mtime, owner 0, `gzip -n`; rebuilding from the same files gives the same sha256. Release `gauntlet-corpus-2026-10` on `dwarvesf/dwarves-kit`, `--latest=false`, so `v2.3.0` stays latest. |
| 3 | Readers that needed a change: `lib/gauntlet/stats.sh` (names the missing corpus on stderr and in the render; token and cost columns stay `-`, as before), `skills/gauntlet-proof-audit/SKILL.md` (fetch per CORPUS.md before Tier 2, else UNSURE), `tests/test-adopt.sh` (it read a real gauntlet transcript as its omp-shape fixture; now a 7-line synthetic fixture, `tests/fixtures/onboarding-cost/omp-transcript.jsonl`). |
| 4 | Readers left alone: everything that reads only `ROUNDS.md`, findings, patches and `checker-output.txt`; the gauntlet runners (`gauntlet-ab`, `gauntlet-campaign`, `cleanroom/*`), which write transcripts for a NEW run and are now covered by the `.gitignore` rule. Other `transcript.jsonl` hits are unrelated Claude Code session logs. |
| 5 | With the corpus unpacked, `stats.sh` reproduces the committed 2026-09-01 snapshot token and cost numbers exactly. Checked by unpacking the downloaded asset into the tree, running stats, then moving the files out. |
| 6 | The unpacked files are git-ignored, so fetching the corpus never dirties the tree. |
| 7 | History still holds the blobs, so clone size does not shrink; only the working tree does. Rewriting history is out of scope and was not approved. |
