# Verification -- truncate-class-false-positive

The data-loss floor no longer fires on a Tailwind `truncate` class; SQL `TRUNCATE` in code strings still does.

## Green run
```
Command: bash tests/test-lanes-data.sh floor_data_loss
Exit: 0
Output:
  PASS floor-data-loss
Verdict: PASS
```
The full file (`bash tests/test-lanes-data.sh`) has no FAIL line, and `bash tests/test-lane-classify.sh` ends `38/38 passed, 0 failed`.

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-lanes-data.sh floor_data_loss" "git show origin/master:lib/classify/lane-classify.sh > lib/classify/lane-classify.sh"
Exit: 1 (under mutation, RED expected)
Output:
  FAIL floor-data-loss:  [<span className="truncate text-[13px] text-grey-400">{r.to}</span> in ui/Row.tsx should not hit: 'full data-loss: ui/Row.tsx'] [<div className="truncate flex">{r.name}</div> in ui/Row.tsx should not hit: 'full data-loss: ui/Row.tsx'] [const c = cn("truncate max-w-xs", extra) in ui/Row.tsx should not hit: 'full data-loss: ui/Row.tsx']
Verdict: PASS (RED under the old regex, green after restore)
```
Restored with `git checkout HEAD -- lib/classify/lane-classify.sh`.

## Not proven
- A line that carries both a class attribute and a real SQL `TRUNCATE` is skipped by the class-attribute exclusion.
- A bare-word utility outside a class attribute (`cn("truncate flex")`) still matches.
