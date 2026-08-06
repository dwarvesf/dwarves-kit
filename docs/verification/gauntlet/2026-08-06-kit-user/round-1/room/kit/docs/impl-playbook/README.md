# Implementation playbook: maintenance

This folder holds reference files for implementation rules by language and architecture area, distilled from named external sources (style guides, standards, well-known essays) instead of invented from scratch.

## How to tell if a file is still correct
Every file ends with a `Sources` list (direct links to what it distills) and a `Verified` date, the last time those sources were actually re-read and compared against the file's content. A `Verified` date does not mean the rule is timeless, it means it was true as of that date. Trust a file dated within roughly the last year; treat an older one, or any file whose cited source has visibly moved on (a new major style-guide version, a deprecated API, a superseded standard), as due for a refresh before relying on it for something that matters.

## When to refresh a file
- A cited source ships a new major version (a new OWASP Top 10 edition, a new ASVS version, Cloudflare deprecating a documented pattern).
- Real work turns up a case where the file's rule was wrong or the source has clearly moved past it.
- Otherwise, no fixed schedule. This is a personal-scale reference, not a compliance artifact: refresh on friction, not a calendar.

## How to refresh a file
1. Re-open the file's `Sources` links, or search for the source's current canonical location if a link has moved.
2. Compare the live source against the file's content and note what changed.
3. Edit the file in place (never create a parallel v2 file); update the `Verified` date to today.
4. Commit on a small branch/PR, same pattern as the original build: `docs(claude): refresh <file> against <source>`.

## How to add a new file
For a from-scratch topic (a new language, a new architecture area), the original build dispatched one research subagent per topic, each asked to cite concrete URLs and give a recommendation, then distilled the findings into a file with the same `Sources` + `Verified` footer. That is the repeatable recipe, not just for refreshing but for extending this playbook.
