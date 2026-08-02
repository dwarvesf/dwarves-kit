# Exploratory testing rules

Distills James Bach & Michael Bolton's definition of exploratory testing plus Session-Based Test Management (Jonathan and James Marcus Bach, 2000). `test-case-design.md` covers scripted, decided-in-advance cases (EP/BVA/decision tables); this file covers what a QA engineer does when the scripted cases run out, deliberate, skilled investigation that finds what the design didn't anticipate. Cross-language; applies on top of whichever per-language file governs the code being written, same as `coding-hygiene.md` and `security.md`.

## What exploratory testing actually is

Not "randomly clicking around." Bach and Bolton define it as treating test design, test execution, and learning as one activity running in parallel, not a separate design phase followed by mechanical execution. Each result you observe informs the next thing you try, the way scripted cases (decided before you ever ran the code) cannot.

## Session-Based Test Management: the disciplined form

Unscripted testing without structure produces no record of what was actually covered. SBTM fixes that with three pieces:
- **Charter**: a one-line stated mission before you start, what you are testing or what problem you are hunting for. Without a charter, exploration drifts into whatever is easiest to poke at, not what is riskiest.
- **Time-boxed session**: a fixed block (45 minutes short, 90 minutes typical, 120 minutes long, per the original HP practice) with one charter. Stopping at the boundary forces a decision, keep going under a new charter, or stop and report, rather than open-ended wandering.
- **T/B/S time accounting**: afterward, roughly split the session into Test time (designing and running probes), Bug time (investigating and writing up what you found), and Setup time (environment, fixtures, data). A session that is all Setup time means the charter picked a target that was not actually ready to test.

## When to reach for it

After the scripted cases from `test-case-design.md` pass, not instead of them. Scripted cases check the shapes you already thought of; a short exploratory pass catches the shape you didn't. Reach for it on anything with real integration points, a UI/CLI flow, or a feature whose actual runtime behavior might drift from what the spec describes, exactly the gap the router intro's "floor, not ceiling" line points at, applied specifically to testing.

## At personal scale

Skip the formal session report and metrics tracking, that overhead is for an auditable QA team, not a solo maintainer. Keep the three ideas in lightweight form: state the one-line charter before you start poking, time-box it (15-30 minutes is plenty for a personal-scale tool, not 90), and if a session turns out to be mostly Setup time, that is itself a finding, the thing was not ready to explore.

## Sources
- [Exploratory Testing Explained (James Bach)](https://satisfice.us/articles/et-article.pdf)
- [Session-Based Test Management (James Bach, Jon Bach)](https://www.satisfice.com/download/session-based-test-management)

Verified: 2026-08-03.
