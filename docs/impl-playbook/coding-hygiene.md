# Code hygiene and senior-engineer discipline

Distills the Twelve-Factor App's config principle (factor III) and standard clean-code discipline on naming, magic values, and duplication. Cross-language; applies on top of whichever per-language file governs the code being written.

## No hardcoding
- Anything that changes between environments (URLs, ports, file paths, feature flags, credentials) is config, never a literal in source. Config comes from environment variables or a config file, per the Twelve-Factor App's "store config in the environment" rule, not per-environment branches hardcoded into the code.
- A magic number or magic string used more than once, or whose meaning is not obvious from context, becomes a named constant. If the same constant is needed in more than one file, it gets one canonical definition, not copies.

## Constants organization
- Group related constants together (one file or module per domain), not one giant catch-all constants file for unrelated values.
- Name a constant for what it means, not its value: `MAX_RETRY_ATTEMPTS`, not a bare `3` repeated at call sites.
- A related set of constants uses the language's actual enum or union mechanism (per the language-specific file above), not a loose set of unrelated top-level constants.

## Naming and function size
- A name should make a comment unnecessary. If a variable needs a comment to explain what it holds, rename it instead.
- A function that needs a paragraph of comments to explain what it does is a split candidate.
- Prefer several small, well-named, single-purpose functions over one large function with internal section-comment dividers.

## Duplication
- The same logic in two or more places is a bug waiting to happen, since only one copy gets fixed. Extract to one shared function once a third occurrence appears (the rule of three); extracting on the first duplication is premature abstraction.

## Sources
- [The Twelve-Factor App, III. Config](https://12factor.net/config)
- Clean Code (Robert C. Martin), chapters on naming and functions, the canonical source for the naming/magic-value/function-size rules above.
- Refactoring (Martin Fowler), the rule of three on duplication, credited to Don Roberts.

Verified: 2026-07-29.
