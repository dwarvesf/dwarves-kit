# Implementation notes: board-row-gate

Delta from the brief (extend ops-toolkit's commit-msg board-row gate to every repo with a board, as a PreToolUse Bash hook). Only the choices the brief left open are recorded.

## Root BACKLOG.md counts as a board too

Context: the brief named `_meta/BACKLOG.md`. About half the boards in the operator's registry keep `BACKLOG.md` at the repo root (books, trading, console-labs, properties, hedgenotes, fromwu, webuild, vibedex, danny-studio).
Decision: the hook checks `_meta/BACKLOG.md` first, then root `BACKLOG.md`.
Why: the goal is every repo with a kit board. A `_meta/`-only check would miss half of them. The first-cell ID shape keeps a stray non-kanban BACKLOG.md from matching.

## Compare ID sets, not diff lines

Context: the reference hook parses `git diff --cached` added lines.
Decision: the hook extracts first-cell IDs from the content being committed and from `HEAD:<board>`, then takes the set difference.
Why: the two are equivalent for new-row detection, and the set form handles `-a` and pathspec commits by reading the working-tree file instead of the index. Moves and flips fall out for free.

## Message parsing is regex over the command text, bash only

Context: the kit forbids Python and Node in hooks (PHILOSOPHY). The common agent shape is `-m "$(cat <<'EOF' ... EOF)"`.
Decision: heredoc bodies are split out with awk first, then `-m`/`--message` values (double, single, `$'...'`, bare) and `-F`/`--file` paths are read by bash regex. A literal `\n` inside one double-quoted `-m` stays literal, as in bash, so it yields no marker line.
Impact: an unusual shape the regex misses counts as "no marker", which blocks only when new IDs exist. That is the fail-closed direction the brief asked for.

## On by default, per-repo opt-out through [gate]

Context: the kit's quality gates are opt-in through `[gate]` keys in `lib/gate/gate-policy.sh`. A first cut had no key, only the env kill switch. The lead asked for default ON plus a per-repo opt-out, so other engineers adopting the kit can switch it off.
Decision: a new `[gate] board_row_gate` key, the one gate key that defaults to `true`. The default lives in two places: `DEFAULT_ON` in `gate-policy.sh` (the code default when no file names the key) and the kit-root `kit.toml`. A repo opts out with `false` in its `.kit.toml`; the operator overlay can switch it off machine-wide.
Why `[gate]` and not a `[board]` section: `gate-policy.sh` is the one reader hooks may call, and it already carries the rule that a project `false` applies only once `.kit.toml` is committed and clean. So an agent cannot switch the gate off with an uncommitted edit in the same session. A new section would need a second reader to repeat that rule.
Impact: the hook asks the policy only after it finds a new ID, so a commit with no new row pays nothing. The session kill switch `DWARVES_KIT_SKIP_BOARD_ROW_GATE=1` stays for the operator.

## Read what the commit takes, not only the index

Context: the review of the first cut found that `git add -A && git commit` in one Bash call slipped through. PreToolUse runs before the add, so the index lacked the row.
Decision: the hook unions the working-tree board into what it checks when a `git add`/`rm`/`mv`/`stage` earlier in the command reaches the board (`-A`, `-u`, `.`, `:/`, a glob, `_meta`, or the board path), or when the commit uses `-a` or a covering pathspec. A pathspec that leaves the board out passes. Pathspecs count only when each names a real path, because git refuses one that matches nothing; a word that names no path means the parse misread the command.
Impact: a `git restore --staged <board>` earlier in the same call still blocks. That errs toward blocking, and splitting the call clears it.

## One commit per command, its own segment only

Decision: the hook checks the first `git commit` at command position. Its message comes from that commit's segment, up to the first unquoted control operator, and from the heredocs opened inside that segment.
Why: a marker written by a later command in the chain is not in the commit message. Checking every commit of a chain would mean running the whole pipeline per match; agents rarely chain two commits in one call.

## Install module: board

Decision: the bash-installer path wires the hook with the `board` module, beside `backlog-stage.sh`. The plugin path wires it unconditionally through `hooks/hooks.json`, like every other kit hook.
