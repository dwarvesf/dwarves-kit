# Collaborative Design Protocol

> This file is referenced by agent prompts and commands that need structured decision-making.
> It is NOT a standalone command or agent. It's a shared protocol definition.
> Source: CCGS Collaborative Design Principle (Question > Options > Decision > Draft > Approval)

## When to invoke this protocol

Any agent or command should invoke this protocol when:
- There are 2+ valid implementation approaches and the choice materially affects the outcome
- A decision is irreversible or expensive to undo (data model, API contract, architecture pattern)
- The spec is ambiguous and the agent must interpret intent

Do NOT invoke for:
- Obvious single-approach tasks (fix a typo, add a missing import)
- Style decisions covered by project rules (naming, formatting)
- Decisions already made in the spec's Decision Log

## The 5-step protocol

### Step 1: Question
State the decision clearly in one sentence.
```
DECISION NEEDED: Should user auth use JWT tokens or session cookies?
```

### Step 2: Options
Present 2-3 options. Each option must include:
- What it is (1 sentence)
- Key tradeoff (what you gain, what you lose)
- Conditions where this option wins

```
OPTION A: JWT tokens
  + Stateless, scales horizontally, good for API-first
  - No server-side revocation without blacklist
  Best when: multiple clients (web + mobile), microservices

OPTION B: Session cookies
  + Server-side revocation, simpler security model
  - Requires session store (Redis), sticky sessions for scale
  Best when: single web app, strong revocation requirements

OPTION C: JWT + refresh token rotation
  + Stateless access + revocable refresh
  - More complex, two token types to manage
  Best when: need both API flexibility and revocation
```

### Step 3: Recommendation
State which option you'd pick and why. Be specific.
```
RECOMMENDATION: Option A (JWT tokens)
REASON: The spec describes an API consumed by web + mobile. No revocation
requirement is mentioned. JWT is simpler for this use case.
```

### Step 4: Decision
- **Lead mode**: Pause and ask the human. Present the options using AskUserQuestion if available, or as a formatted choice in the response.
- **Coder mode / subagent**: The orchestrator or verifier agent picks. If the recommendation aligns with the spec, proceed with it. If it contradicts the spec, escalate.
- **Autonomous mode** (/execute): Proceed with the recommendation. Log the decision. The task-verifier will catch misalignment.

### Step 5: Record
After a decision is made, append to `.planning/SPEC.md` Decision Log:
```
- DEC-[N]: [decision] -- [rationale] -- [alternatives rejected] -- [who decided: human/orchestrator/auto]
```

## For agent authors

Include this line in your agent prompt to activate the protocol:
```
When you encounter a decision with 2+ valid approaches, follow the Collaborative
Design Protocol in docs/COLLABORATIVE-DESIGN.md. Present options, recommend one,
and proceed according to your mode (lead/coder/autonomous).
```

## For commands that dispatch agents

When dispatching a worker subagent, include the mode in the context block:
```
## Decision mode
[lead: pause for human approval / autonomous: proceed with recommendation and log]
```

The orchestrator in /execute should default to `autonomous` for worker subagents (the verifier catches bad decisions after the fact) and `lead` when the user is running /next manually.
