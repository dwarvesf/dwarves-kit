# Threat modeling and secure-by-design rules

Distills STRIDE (Microsoft's threat-modeling framework) and the OWASP Threat Modeling Cheat Sheet. Purpose: think like an attacker before or while writing code, so the design resists realistic exploitation instead of only passing a checklist after the fact. Complements `security.md` (the coding-time rule list); this file is the "what could go wrong here" lens that decides which of those rules actually matter for a given feature.

## STRIDE: six questions to ask about any new feature or component
- Spoofing: can someone pretend to be a user or service they are not? (identity, authentication)
- Tampering: can someone modify data or code in transit or at rest without detection? (integrity, signing, checksums)
- Repudiation: can an action happen with no trace of who did it? (logging, audit trail)
- Information disclosure: can data reach someone who should not see it? (encryption, access control, least privilege)
- Denial of service: can someone make this unavailable to legitimate users? (rate limiting, resource caps)
- Elevation of privilege: can a low-privilege actor gain higher privilege? (authorization checks, sandboxing)

Run this as a five-minute pass on any feature that crosses a trust boundary (accepts external input, talks to another service, stores user data). Skip it for pure internal utility code with no external input.

## Verifying a suspected authorization gap
Read the code and reason about it, then PROVE it live rather than trust the reasoning. From the lower-trust side, send a request carrying a deliberately INVALID value (a nonexistent record, an unknown alias) to a route that should be out of reach. A hard rejection before the request is even parsed means the boundary held. An application-level error that names real schema (`unknown database "x", allowed: A, B, C`) means the request passed authentication and reached business logic, which proves reachability without ever touching real data. Keep this negative-value probe in the proof-of-done next to the fix, not only in the finding writeup, so the next reader can re-run it instead of re-deriving it.

## Defense-in-depth defaults
- Assume any single layer can fail; do not rely on one control (app-level validation and a DB constraint, not just one).
- Fail closed, not open: an auth check that errors should deny access, not grant it.
- Least privilege by default (also in `security.md`): a component gets only the access its one job needs, nothing broader "in case."
- Do not trust the network, even internal traffic: authenticate service-to-service calls; a private network is not a security boundary by itself. Exception, stated so it is not silently overridden: when the CALLER is untrusted code (an LLM-driven sandbox) that must never hold a credential at all, giving it one to authenticate with is worse, since it becomes a secret that caller can leak, not a control. There, isolating callers of different trust onto separate networks IS the boundary, and the real credential stays server-side, injected only by the process sitting on the higher-trust network.
- A safety invariant that lives only as a comment or a second, independently maintained data structure is not a control. Nothing re-checks it when the surrounding code changes, so it drifts, and the drift is silent by construction. Verified live twice in one session: a comment claiming a shared route "never moves money without a human downstream" stopped being true a few commits later with nobody re-reading it, and a network mapping restated in a second script location silently stopped covering a newly added consumer. Derive the second copy from the first's actual output; never re-encode the same decision independently.
- Splitting a shared credential into per-consumer copies needs two assertions, not one: that a lower-trust consumer does NOT hold the higher-trust credential, AND that the higher-trust consumer still HOLDS what its own routes need. The first alone can ship an outage disguised as a fix, since a split that quietly drops a still-needed key fails closed in a way indistinguishable from a successful hardening pass until something calls that route.

## When this becomes a real red-team engagement
If the next step is an actual authorized penetration test or red-team exercise, not just designing your own code defensively, that is a separate gated process. See `red-team-engagement.md` for the rules-of-engagement gate and the PTES phase list.

## Sources
- [Threat Modeling Cheat Sheet (OWASP)](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [The STRIDE Threat Model (Microsoft Learn, archived Commerce Server docs)](https://learn.microsoft.com/en-us/previous-versions/commerce-server/ee823878(v=cs.20))
- [Microsoft Learn: Threat modeling (current)](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) (the archived link above can vanish without notice)

Verified: 2026-08-09.
