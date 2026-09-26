# SPEC-900: nightly inbox summarizer

**Status:** DRAFT
Lane: normal
Type: spec-feature

## Problem

The operator reads 200 support emails a day. A nightly summary would save an hour.

## Contract

- A launchd agent `mini.inbox-summary` runs `bin/inbox-summary` at 02:00 every night on the Mac Mini.
- The script pulls every email received in the last 24 hours over IMAP, sends each one to the Claude API for a two-line summary, and posts the joined summaries to the #support Discord channel.
- IMAP and Anthropic API keys are read from a `.env` file next to the script.
- The script uses the `imap-tools` Python package pinned at the latest version.

## Picture

```
 launchd 02:00 --> bin/inbox-summary --> IMAP (last 24h) --> Claude API (per email) --> Discord #support
```

## Design

Chosen approach: one Python script, one model call per email, one Discord post.

Approaches considered:

| Approach | Why not |
|---|---|
| One model call for the whole batch | long batches exceed the context window |
| A hosted Zapier flow | extra vendor |

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| IMAP login fails | script exits non-zero | retried the next night |
| Claude API 5xx | exception per email | that email is skipped |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: script | `bin/inbox-summary` | posts a summary for a test mailbox |
| T2: plist | `deploy/mini.inbox-summary.plist` | launchd loads it |

## Verification

Run `bin/inbox-summary --dry-run` against a test mailbox; it prints summaries.

## After state

Every morning #support has a summary of yesterday's email.
