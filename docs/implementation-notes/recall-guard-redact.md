# Implementation notes: recall guard + redaction (battery fixes over #482)

The spec is the battery report over #482 (security MED 3-4, LOW 6; reviewer M5, M6, L7-L10;
advisor M3-M4). This note carries only what those findings left open.

## 2026-09-04 00:55 the `--sessions` name stays

Context: the advisor flagged `session recall X --sessions` against `session observe sessions`.
Decision: keep the flag. They sit one level apart, the flag reads as "group recall hits by
session", and renaming a flag shipped the same night buys a churned README for no caller.
Revisit only if a `session sessions <verb>` grammar is ever added.

## 2026-09-04 00:55 walk newest-first, stop at --limit

Decision: `--sessions` sorts the project's transcripts by mtime descending and stops loading
once `--limit` hits are found; the header says `(capped by --limit, raise it for more)` when
the walk stopped, instead of posing as a total.
Why: the live run loaded 1264 files to print 5 rows (reviewer M5), and the old header printed
the post-slice count as if it were the total (L7).
Tradeoff: no true total is known when capped; a count would cost the full walk the fix
removes. `--limit 0` is not special-cased.

## 2026-09-04 00:55 union of project dirs is named, not hidden

Decision: when a short name resolves to more than one dir, the header lists them. The union
itself stays (a repo checked out twice is one project to a human).

## 2026-09-04 00:55 not done

- `--since 24h` (advisor keep): `--limit` over a newest-first walk covers the common case;
  not built until a real ask.
- `opening_ask` on a session driven only by slash commands stays empty (advisor M4): the row
  keeps its id, mtime and hit count, which is enough to open it.
