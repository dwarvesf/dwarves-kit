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

## Defense-in-depth defaults
- Assume any single layer can fail; do not rely on one control (app-level validation and a DB constraint, not just one).
- Fail closed, not open: an auth check that errors should deny access, not grant it.
- Least privilege by default (also in `security.md`): a component gets only the access its one job needs, nothing broader "in case."
- Do not trust the network, even internal traffic: authenticate service-to-service calls; a private network is not a security boundary by itself.

## When this becomes a real red-team engagement
If the next step is an actual authorized penetration test or red-team exercise, not just designing your own code defensively, that is a separate gated process. See `red-team-engagement.md` for the rules-of-engagement gate and the PTES phase list.

## Sources
- [Threat Modeling Cheat Sheet (OWASP)](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [The STRIDE Threat Model (Microsoft Learn, archived Commerce Server docs)](https://learn.microsoft.com/en-us/previous-versions/commerce-server/ee823878(v=cs.20))
- [Microsoft Learn: Threat modeling (current)](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) (the archived link above can vanish without notice)

Verified: 2026-07-29.
