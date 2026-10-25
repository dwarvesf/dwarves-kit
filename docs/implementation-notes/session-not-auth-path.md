# Implementation notes: session-not-auth-path

No spec. The format and guards come from `docs/specs/SPEC-400-shipgate-fixture-hardpath.md` and ADR-0039. No deviations from them.

- The entry covers `lib/session/**` for kind `auth` only. A narrower glob would list each subdirectory and rot as the tooling grows.
- The test reads the repo's real `.kit.toml` rather than a hand-copied entry, so deleting or widening the entry turns it red.
- The parked relief attempt (an older exemption design with host-scoped entries) was read for context only. Nothing from it was reused.
