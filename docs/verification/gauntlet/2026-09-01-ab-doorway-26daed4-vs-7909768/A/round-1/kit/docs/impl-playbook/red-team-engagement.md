# Authorized security-testing engagement rules

Distills PTES (methodology), OWASP WSTG (web test taxonomy), NIST SP 800-115 (compliance cross-check), and MITRE ATT&CK (reporting taxonomy). Process and methodology only. This file holds no exploit techniques.

## Gate: nothing starts without signed rules of engagement
Before any test, a written RoE must cover: scope (assets, exclusions), the time window plus blackout periods, permitted techniques and hard no-gos (is social engineering, DoS, or physical intrusion allowed), the emergency contact on both sides, the critical-finding escalation procedure, data-handling rules for anything captured during the test, and the signed authorization line. The SANS RoE Worksheet is the template to start from.

## Phase list (PTES)
PTES's phase structure below is still the common reference framing, but the standard itself is dormant: pentest-standard.org's own pages carry edit timestamps from the early-to-mid 2010s with no update since. Treat it as a naming/structure convention, not an actively maintained standard, cross-check specifics against WSTG (current, v4.2) or ATT&CK (current, v19.1) rather than PTES.

1. Pre-engagement: scope, RoE, authorization, statement of work.
2. Intelligence gathering: OSINT, recon, enumeration.
3. Threat modeling: map intel to relevant threat-actor profiles, prioritize attack vectors.
4. Vulnerability analysis: scanning plus manual inspection. For web-app scope, use OWASP WSTG's category checklist (one WSTG-ID per test) as the concrete test menu.
5. Exploitation.
6. Post-exploitation.
7. Reporting: tag each finding with its MITRE ATT&CK technique ID, so the report is comparable across engagements and consumable by a blue team. ATT&CK is a reporting taxonomy, not a phase. It does not replace the phase list above.

## Compliance cross-check
NIST SP 800-115 is the government/compliance-flavored equivalent (Planning, Execution, Post-Testing/Reporting). Some clients require its structure verbatim. Check the statement of work before assuming PTES's framing is sufficient.

## Sources
- [PTES (community mirror)](https://pentest-standard.readthedocs.io/)
- [OWASP Web Security Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- [NIST SP 800-115](https://csrc.nist.gov/pubs/sp/800/115/final)
- [MITRE ATT&CK](https://attack.mitre.org/)
- [SANS Pen Test Rules of Engagement Worksheet](https://www.sans.org/posters/pen-test-rules-of-engagement-worksheet)

Verified: 2026-08-03.
