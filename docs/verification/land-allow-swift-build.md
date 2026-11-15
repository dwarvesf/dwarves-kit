# Verification -- land allows SwiftPM and script build output

`wrap land`'s ignored-file guard now always allows `build` and `.build`, so a Swift package worktree holding `mac/.build/` and `mac/build/` lands.

## Green run
```
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0
Output:
--- 4k: SwiftPM and script build output (.build, build) passes; a non-build ignored file still refuses
  PASS 4k: fixture check: both build dirs are ignored
  PASS 4k: mac/.build/x and mac/build/x exit 0
  PASS 4k: no refusal
  PASS 4l: data/secret.json beside the build dirs exits 1
  PASS 4l: names data
  PASS 4l: does not name the build dirs
  PASS 4l: no push
  PASS 4l: no PR create, edit, ready or merge
test-wrap-land: LAND_ONLY='ignored' selected 1 of 18 sections
test-wrap-land: all 100 passed
Verdict: PASS
```
The new cases: 4k (a `mac/.build/debug/x` and a `mac/build/x` pass) and 4l (a `data/secret.json` beside both still refuses, nothing pushed).

## Negative control
The `_LAND_IGNORED_BUILTIN` line in `lib/wrap/wrap-land.sh` put back to its old value by hand (`build .build` removed), the same command run, then the new line restored and the suite green again.
```
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL 4k: mac/.build/x and mac/build/x exit 0
  FAIL 4k: no refusal
  FAIL 4l: does not name the build dirs
test-wrap-land: 97 passed, 3 FAILED of 100
Verdict: PASS (the control went RED on the new allow cases, 4l's refusal cases stayed green)
```

## Not proven
- The matcher is a bare-name last-component glob, so any ignored file literally named `build` or `.build` also passes; that is the same trade the existing `dist` and `target` entries make.
- No real SwiftPM package was built; the fixture stands in for its ignored output.
