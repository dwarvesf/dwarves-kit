# Verification -- shots fall back to any installed Chromium browser

With no `CHROME` set, `lib/system-design/shots.mjs` tried only Google Chrome, so `doc-figures render` failed on a Mac without it (spawn ENOENT). It now takes the first installed of Chrome, Edge, Brave, Chromium or Helium.

| Check | Result |
|---|---|
| `doc-figures render docs/figures/MODEL.md` with CHROME unset, on a Mac without Chrome | 12 figures rendered |
| tests/test-doc-figures.sh | 50 passed, 0 failed |
| Negative control: the old shots.mjs | render exits 1, green after restore |

## Green run
```
Command: env -u CHROME bash lib/system-design/doc-figures render docs/figures/MODEL.md <scratch>; bash tests/test-doc-figures.sh
Exit: 0
Output:
  rendered 12 png figures into <scratch>
  doc-figures: 50 passed, 0 failed (50 checks)
Verdict: PASS
```

## Negative control
```
Command: negctl.sh <repo> "env -u CHROME doc-figures render ..." "git show origin/main:lib/system-design/shots.mjs > lib/system-design/shots.mjs"
Exit: 1 (under mutation, RED expected)
Output:
  Error: spawn /Applications/Google Chrome.app/Contents/MacOS/Google Chrome ENOENT
Verdict: PASS (restored, green after restore)
```

## Rollback
- Revert the merge commit; CHROME must then be set on a Mac without Chrome.
