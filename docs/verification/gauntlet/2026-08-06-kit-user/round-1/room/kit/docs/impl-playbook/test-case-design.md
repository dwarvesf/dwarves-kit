# Test case design and UAT rules

Distills the ISTQB CTFL black-box test design techniques plus Cucumber's Gherkin reference for acceptance criteria. `testing-strategy.md` covers WHICH layer deserves a test; this file covers HOW to design the individual cases so the input space is actually covered, not just the happy path, plus how to write UAT scenarios a non-engineer can sign off on. Cross-language; applies on top of whichever per-language file governs the code being written.

## Four black-box techniques (pick the ones that fit the input shape)

- **Equivalence partitioning**: group inputs that should behave identically, test one value per group instead of every value. An age field taking 18-65 partitions into under-18 / 18-65 / over-65.
- **Boundary value analysis**: extends EP to the edges of each partition, because off-by-one bugs cluster there. For 18-65, test 17, 18, 19, 64, 65, 66, not just one interior value.
- **Decision table**: when an outcome depends on a combination of conditions (a loan needs income AND credit score AND tenure), enumerate the combinations as rows instead of testing conditions independently, since independent tests miss interaction bugs.
- **State transition**: when the code has explicit states, test the valid transitions (pending → shipped → delivered) AND the invalid ones an attacker or a race condition could trigger (shipped → pending).

## UAT / acceptance criteria (Gherkin Given-When-Then)

- **Given** sets up a known starting state (data, config), never a user action. **When** is the single action or event under test. **Then** asserts an observable outcome (a report, a UI change, a returned value), never an internal implementation detail like a raw DB row.
- Keep each scenario to 3-5 steps. One scenario, one behavior; a scenario that needs "and also" to describe is two scenarios.
- Write the acceptance criteria BEFORE building, agreed with whoever signs off (the stakeholder, or your future self reading it in a month). Ambiguous words ("fast", "works correctly") are not acceptance criteria.

## At personal scale

Solo-maintained tools do not need a decision-table spreadsheet for every function. Reach for these four techniques together only where a bug would be expensive to miss: money paths, auth/permission boundaries, parsers, anything with 3+ interacting conditions. For everything else, EP + BVA on the one or two trickiest inputs is enough; skip decision tables and state-transition diagrams unless the code genuinely has combinatorial conditions or explicit states.

## Sources
- [ISTQB CTFL v4.0.1 Syllabus (PDF)](https://istqb.org/wp-content/uploads/2024/11/ISTQB_CTFL_Syllabus_v4.0.1.pdf)
- [ISTQB CTFL Syllabus, 4.2 Black-Box Test Techniques (ASTQB, derived page)](https://astqb.org/4-2-black-box-test-techniques/)
- [Gherkin Reference (Cucumber docs)](https://cucumber.io/docs/gherkin/reference/)

Verified: 2026-08-03.
