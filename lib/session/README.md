# session

Tools that read Claude Code session data: transcripts, usage stats, past decisions, and open handoffs. They let a live session find prior work instead of re-deriving it.

**Entry points**
- `lib/session/session.sh <verb>`: the dispatcher. `bin/session` forwards to it.
- `session audit`: LLM deep-audit of transcripts. See `lib/session/audit/README.md`.
- `session intel`: weekly read-only digest of usage and repo health. See `lib/session/intel/README.md`.
- `session observe`, `session report`, `session semantic`: usage and latency stats. See `lib/session/observe/README.md`.
- `session recall`: turn-grouped search over raw transcripts. See `lib/session/recall/README.md`.
- `lib/session/handoffs.sh list|archive`: list open handoff files, or move a finished one into `archive/`. Not routed through `session.sh`.
- `lib/session/parse-transcript.sh <transcript.jsonl>`: print one JSON object per parsed transcript line.

**Layout**
- `parse_transcript.py`: the shared JSONL parser that `observe` and `recall` import. The shell file above only launches it.
- `audit/`, `intel/`, `observe/`, `recall/`: the sub-tools, each with its own `bin/` and README.

**Tests**: `lib/session/tests/` holds the handoff and parser suites, with `fixtures/`. The root suite `tests/test-session-recall.sh` covers recall. Run `bash tests/run-all.sh --only session`.
