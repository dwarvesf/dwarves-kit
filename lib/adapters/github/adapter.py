"""The GitHub Issues adapter: builds the GitHub spoke."""
from __future__ import annotations

from github import GitHubSource


def build(app, opts, ctx):
    # repo empty is fine: gh resolves origin from the backlog's own repo (the project root the engine
    # passes in), never the process cwd, which under launchd is nowhere near the checkout.
    return GitHubSource(opts.get("github_repo") or "", cwd=ctx.project_root)
