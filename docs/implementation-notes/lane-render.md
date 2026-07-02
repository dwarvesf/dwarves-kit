# Implementation notes: lane-telemetry render (SPEC-099)

Delta from SPEC-099.

## 2026-07-02 dispatch must forward args (caught in test)

`render` takes an optional filter, but `main()`'s `case` dispatched `render)   render ;;`
without `"$@"`, so `render full` silently rendered ALL runs. Fixed to `render) render "$@" ;;`.
The filter test caught it (the full-render and filtered-render outputs were identical). Lesson:
a subcommand that takes args needs `"$@"` in the dispatch; `report`/`misfires` took none so the
pattern wasn't there to copy.

## 2026-07-02 gate-coverage respects the filter

First cut computed gate coverage by globbing `$RUNS_DIR/*.log` directly, which ignored the
filter (a filtered render showed corpus-wide coverage). Reworked to build the file list from
the filtered rows' rids so the coverage section matches the table + flow.

## 2026-07-02 dogfood win

SG-04 itself classified `full` at intake because SG-03 added `lane-telemetry` to the
kit-machinery hard-gate one PR earlier. The wave's own fix corrected the wave's own lane.

## 2026-07-02 no filter grammar

DEC-002: the filter is a bare substring match on lane OR type, not a `--lane=`/`--type=` flag
pair. One positional arg covers the common asks ("full", "eval") and keeps the surface tiny
(ponytail); a flag grammar would be speculative for a read-only view.
