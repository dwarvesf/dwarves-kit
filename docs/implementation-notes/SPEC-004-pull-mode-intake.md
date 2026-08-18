# Implementation notes, SPEC-004 pull-mode intake

Delta from the spec only. The spec is the contract; this file records what the
build decided that the spec left open, and what it deliberately did not do.

## 2026-08-18 10:00 Duplicated ntn transport helpers instead of extracting them

Context: `_run_ntn` and `_plain` now exist in three adapters
(`notion.py`, `notion_taskboard.py`, `notion_taskboard_pull.py`).

Decision: duplicate them in the new adapter rather than extract a shared
`sources/_ntn.py`.

Why: the kit's own rule says abstract at the third occurrence, which this is.
The competing rule is surgical change, and extraction means editing two shipped
adapters inside a feature branch that has no other reason to touch them. The
duplicated surface is 15 lines with no branching. A reviewer reading the diff
should see one new posture, not a refactor of two working ones.

Alternatives: extract now (larger diff, two working adapters at risk); import
the private helpers from `sources.notion` (couples adapters through a private
name, worse than the copy).

Impact: the next adapter that needs an `ntn` transport should extract, and it
gets a diff limited to that change.

Open questions: none.

## 2026-08-18 10:20 The pull app is not listed in `apps`

Context: the spec requires exactly one clone to run intake, but `.kit.toml` is
git-tracked, so any `apps` entry reaches every clone that runs `board sync`.

Decision: the app is configured by its `notion_taskboard_pull_*` keys but is
never added to `apps`. The runner names it on its own invocation
(`board sync --apps notion-taskboard-pull`), which works because `cmd_sync`
forwards user flags after config-derived ones and argparse lets the later win.

Why: it makes the single-runner requirement a property of where the invocation
lives (one host's job definition) rather than of a shared config file every
clone reads.

Alternatives: a host-matching config key (new machinery for one consumer); a
`.kit.local.toml` layer (kit-config has no such layer today).

Impact: `kit.toml` documents the keys with a comment saying the app runs alone;
the engine refuses a shared invocation regardless, so a misconfiguration fails
loudly instead of duplicating agent tasks.

Open questions: none.

## 2026-08-18 10:35 `next_id` poisoning flagged, not fixed

Context: `sync_core.next_id` regexes `\b<PREFIX>-\d+\b` over the whole board
text, not over parsed row ids, so any text in a notes cell can move the id
counter. Every intake path reaches it, Reminders included.

Decision: neutralize board-id tokens in this source's untrusted fields, and
leave `next_id` alone.

Why: the neutralization closes the path this feature opens. Changing `next_id`
changes id minting for every intake path in the engine, and a regression there
is worse than the bug it fixes. It deserves its own row and its own test.

Alternatives: fix `next_id` here (root cause, but out of this feature's blast
radius and untested against the Reminders path).

Impact: recorded in the spec's design question 4 and in its out-of-scope list.
The root fix needs a board row.

Open questions: whether `next_id` should read parsed rows or a dedicated id
index; the parsed-rows form is prefix-scoped and would ignore ids on rows of
another prefix, which may be the desired behavior or may be a second bug.

## 2026-08-18 11:00 Spec test plan renumbered after validation

Context: the draft spec listed 18 test rows. The three adversarial lenses added
cases (prefix flip, broken row, cold-binding allowlist, nonce, title position,
caps, both engine guards).

Decision: the shipped test plan has 31 rows and the suite has 34 tests; the
extra three are the two engine-guard happy paths and a prop-override wiring
case that no acceptance criterion needed but the config plumbing did.

Impact: no acceptance criterion lost a test; the mapping is in the spec table.
