---
name: get-api-docs
description: "Fetch curated API documentation using Context Hub (chub) before coding against any external API. Use when the task involves calling a third-party API (Stripe, OpenAI, Airwallex, Notion, etc.) to prevent hallucinated parameters and deprecated endpoints."
---

# Get API Docs

Before writing code that calls any external API, fetch the curated documentation first.

## When to use

- You are about to write code that calls a third-party API
- You are unsure about the current API parameters, endpoints, or auth method
- The user mentions an API integration (Stripe, Notion, OpenAI, Airwallex, etc.)
- You are debugging an API call that returns unexpected results

## How to use

```bash
# Search for available docs
chub search [api-name]

# Fetch docs (language-specific)
chub get [provider]/[api] --lang [py|js|go]

# Fetch specific reference file
chub get [provider]/[api] --file references/[topic].md

# Fetch everything for comprehensive work
chub get [provider]/[api] --full
```

## After using the API

If you discover something not in the docs (a workaround, a gotcha, a version quirk):

```bash
chub annotate [provider]/[api] "your note here"
```

This persists locally and appears automatically next time you fetch the same doc.

## If chub is not installed

Tell the user: "Context Hub (chub) is not installed. Install it with `npm install -g @aisuite/chub` to get curated API docs and prevent hallucinated API calls."

Then fall back to web search, but warn that the results may be outdated.
