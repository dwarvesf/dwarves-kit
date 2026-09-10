# Proof of done: `learnings` registry kind for `precedent find --surface inventory`

Change: `lib/precedent/inventory.py` accepts a `learnings <dir>` registry row and scans
`<dir>/*/manifest.json` (browser-harness-js per-site recipes) into `learnings/<id>` entries
carrying the name, domains and tool names. A web-control candidate at wrap step 7b now hits
the learning that already drives that site instead of getting a sibling script.

## Recorded run (2026-09-10, Air)

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-precedent.sh` (66 cases, incl. the new `learnings registry row surfaces the manifest as learnings/<id>`) | 0 | PASS 66/66 |
| `PRECEDENT_REGISTRY=<repo + learnings rows> bin/precedent find --surface inventory "tam tru"` against the live harness registry | 0 | PASS `learnings/dvc-cutru` with tools status, open, edit, fill, attach, draft, printCt01, submit |
| same, `"cloudflare token mint"` | 0 | PASS `learnings/dash-cloudflare-com` with whoami, api, mintToken, setZoneSetting |

## Negative control (`lib/gate/negctl.sh`)

```
Command: bash tests/test-precedent.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/elif kind == "learnings":/elif kind == "learnings-off":/' lib/precedent/inventory.py
Changed: lib/precedent/inventory.py
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/precedent/inventory.py
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert the commit; a `learnings` row in an operator registry then prints the unknown-kind
note and the rest of the registry scans as before.
