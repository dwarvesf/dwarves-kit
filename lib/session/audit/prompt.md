Read-only usage-intelligence audit over Claude Code session transcripts: what does
actual usage evidence say about where tokens, time, and attention are wasted, who
owns each fix (the kit, the user's habits, the harness), and what specific changes
would recover them?

Rules: read-only, never modify, move, or delete a transcript. Transcripts contain
secrets (env dumps, tokens, auth headers): never print one; quote any transcript
text at most 150 chars, truncated. Work only under the given root. Every claim
must cite its evidence (a command you ran + its counts, or session-id + line);
an uncited claim is a hypothesis and must be labeled as one.

Sources: JSONL transcripts under {ROOT} (one event per line), modified in the last
{DAYS} days. Sibling directories may hold subagent transcripts of the same work.
{PREV} (optional): path to the previous audit report; when present, open the
report with a metric-by-metric diff against it before any new findings.

Pricing (for dollar attribution; per million tokens):
{PRICING}
The model name is in the logs; convert token findings to $ ranges per model. When
a session mixes models, attribute by the per-message model field, never a blend.
A model with no rate in the table: never price it silently; report its token
share as its own finding and mark every $ total as a floor (or, if you assume a
proxy rate, name the assumption everywhere it is load-bearing).

1. LEARN THE SCHEMA FIRST. Do not grep for guessed event or field names, the
   schema drifts between client versions and a miss reads as a false negative.
   Start with distributions, then inspect one full example of each event kind you
   will rely on:
     jq -r '.type' <file> | sort | uniq -c | sort -rn
   Locate from observation, not memory: user prompts vs assistant turns vs tool
   results, the sidechain/subagent marker, the token-usage block (input, output,
   cache read, cache creation), the model field, timestamps, and the session/parent
   join keys. Note every schema variant you encounter; if a field is absent in
   some files, say which and treat those files as a separate stratum, not as zero.
   Two known transcript traps you must rule out by observation before summing:
   (a) one API response may span several JSONL lines (one per content block),
   each repeating an identical usage block, pick a dedup key (response/message
   id) and state it, or every token total inflates 2-3x; (b) not every
   user-type event is a human prompt, harness injections (hook feedback, task
   notifications, skill-dispatch templates, resume summaries) land as user
   events too; separate them and report the injection share before any
   prompt/rework analysis.

2. CORPUS BASELINE. Before any judgment: session count, event count, date range,
   per-session size distribution (median / p90 / max), sidechain share. Every rate
   you report later is relative to this baseline. State how much of the corpus
   each later measurement actually covered (all files vs a sample), and how the
   sample was chosen.

3. MEASUREMENTS. Prefer aggregate queries (jq/awk across files) over reading
   transcripts; deep-read at most {K} sessions, chosen BY the aggregates (largest,
   most-erroring, most-repetitive), and name them. For each signal report the
   exact command, the counts, and the top offending sessions:

   a. TOKEN ECONOMICS, per-session input / output / cache-read / cache-creation
      from the observed usage fields; the cache-read:fresh-input ratio; sessions
      whose cache reads dwarf their output (mega-context re-read); the largest
      single tool results (paste/dump events) and what produced them. Convert the
      top items to $ using the pricing table and the observed model field.
   b. FRICTION LOOPS, runs of consecutive failed tool calls; the same command
      retried 3+ times in one session; error text repeating across turns.
      Distinguish "retried and recovered" from "abandoned".
      NO DARK BUCKETS: decompose every error bucket that holds more than 10% of
      total errors by the command/tool that produced it, recursively, until no
      bucket over 10% remains unlabeled (a generic "Exit code 1" pile is a
      finding-shaped hole, not a finding).
      ATTRIBUTE HOOK BLOCKS: a "hook blocked this" error names the specific hook
      or gate (they have different owners); report per-hook counts, and for the
      top hook, whether the blocks look self-inflicted (the rule exists and was
      ignored) or systemic (the rule fires where it should not).
   c. REWORK, user prompts that correct or walk back the assistant. Detect by
      pattern, then VERIFY by reading the matched prompts (quote up to 150 chars
      each); report verified count / matched count / sample size separately.
      Never report a rework number you did not read.
   d. REPEATED WORK, near-identical command sequences or prompt intents recurring
      across sessions (candidate automations/skills); recurring startup sequences
      a session replays every time (candidate context or tooling fix).
   e. DELEGATION SHAPE, sidechain share of events and tokens; heavy mechanical
      stretches (bulk grep/read/transform) executed inline in the main context
      where a subagent would have kept the parent small.

4. EVIDENCE TIERS. Label every finding:
     HIGH, deterministic count over an observed field; command shown; anyone
              can re-run it and get the same number.
     MEDIUM, pattern-matched with verified samples (you read a sample and report
              the match-vs-verified rate).
     LOW, model judgment over sampled text (topic labels, intent clusters);
              report the sample size and give ranges, never precise counts.
   Keep tiers separate: never average a LOW estimate into a HIGH total. Where the
   data is ambiguous (an absent usage block: older client, or synthetic event?),
   report the ambiguity and both readings, do not resolve it without evidence.

5. REPORT.
   Metric diff vs {PREV} first, when given: same metrics, old value, new value,
   and whether each earlier recommendation's metric moved.
   Table A, findings: finding, tier, sessions affected, magnitude (tokens, $ or
             occurrences), evidence (the command or the quoted line).
   Table B, recommendations ranked by expected recovery. Each row carries:
             the change; OWNER (kit | user-habit | harness | instrumentation);
             the finding it rests on; expected effect in $ or minutes where the
             pricing/timestamps allow it; confidence; what would falsify it; and
             a METRIC CONTRACT, the metric's name, its current value, and the
             exact re-run command a follow-up audit uses to check movement.
   Then: corpus totals; the {K} sessions deep-read and why; what these logs CANNOT
   answer (and the one instrumentation change that would unblock the strongest
   pending conclusion).

   Claims must not exceed evidence: "N sessions matched pattern P, M of S sampled
   matches verified" is supportable; "the user wastes X because of Y" requires the
   causal chain to be visible in the logs, otherwise write "consistent with".
   Findings with zero occurrences are reported as zeros, not omitted: a clean
   corpus is a result.

   Close the report with the Table B rows repeated once as a fenced ```json
   code block (machine triage reads it; keep it the LAST fenced json block in
   the report). A list of objects, same content as the table, no new rows:
     [{"change": "...", "owner": "kit|user-habit|harness|instrumentation",
       "finding": "...", "effect": "...", "confidence": "high|medium|low",
       "falsifier": "...",
       "metric": {"name": "...", "current": "...", "rerun": "<command>"}}]
