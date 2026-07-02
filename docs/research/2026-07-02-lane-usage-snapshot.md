# Lane-usage snapshot, 2026-07-02 (SPEC-099 / ID-150)

Dated capture of `lane-telemetry.sh render` over the durable run corpus (SG-01). Regenerate
with `bash lib/lane-telemetry.sh render` (add a lane/type filter as an optional arg). This is
a point-in-time snapshot; the live command is the source of truth.

## Full render

```
Lane routing  (18 runs, window 2026-07-01T14:23:09Z .. 2026-07-02T09:47:59Z)

  task-type            lane       runs  gates r/s/o    ships
  -------------------------------------------------------------
  ?                ->  ?             9  51/8/11            0
  bug              ->  full          1  0/0/0              0
  doc              ->  normal        3  9/0/0              3
  docs             ->  normal        1  3/0/0              1
  eval             ->  full          1  12/0/0             1
  reconcile        ->  full          1  12/0/0             1
  spec-feature     ->  full          2  16/0/0             1

  routing flow (task-type -> lane -> gates):

    ?                                        --> ?         (9 runs)
    bug, spec-feature, eval, reconcile       --> full      (5 runs)
    docs, doc                                --> normal    (4 runs)

  gate coverage (runs recording each phase as ran):
    spec             15
    build            15
    think            11
    review           11
    docs             11
    validate         10
    ship             7
    test-plan        6
    design-critique  5
    design           5
    grill            4
    reflect          3

  legend: gates r/s/o = ran / skipped / override summed over those runs;
          "?" lane/type = runs with no START line (untracked; see ID-085).
```

## Filtered render (`render full`, full-lane runs only)

```
Lane routing  (5 runs, filter=full, window 2026-07-02T08:43:16Z .. 2026-07-02T09:47:59Z)

  task-type            lane       runs  gates r/s/o    ships
  -------------------------------------------------------------
  bug              ->  full          1  0/0/0              0
  eval             ->  full          1  12/0/0             1
  reconcile        ->  full          1  12/0/0             1
  spec-feature     ->  full          2  16/0/0             1

  routing flow (task-type -> lane -> gates):

    bug, spec-feature, eval, reconcile       --> full      (5 runs)

  gate coverage (runs recording each phase as ran):
    think            4
    grill            4
    design-critique  4
    design           4
    validate         3
    test-plan        3
    spec             3
    ship             3
    review           3
    reflect          3
    docs             3
    build            3

  legend: gates r/s/o = ran / skipped / override summed over those runs;
          "?" lane/type = runs with no START line (untracked; see ID-085).
```

## Reading it

- `?` lane/type rows are runs with no START line (untracked). At snapshot time they dominate
  (the pre-SG-02 kit-harden corpus); the SPEC-073 eval's metric 3 (ID-085) tracks fixing the
  START-wiring so future snapshots have real lane/type routing for every run.
- `gates r/s/o` = ran / skipped / override summed across those runs.
- `ships` = runs that recorded a `ship` gate.
