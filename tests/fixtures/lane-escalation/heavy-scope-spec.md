# Spec: add password reset endpoint

Status: VALIDATED
Lane: tiny

## Problem
The original task text was "add a password reset link to the settings page", which
read as a tiny cosmetic UI tweak. Writing the spec surfaced real scope: the reset flow
needs a new authentication token, a session refresh path, and a data-model migration
to add a `reset_token` column with a retention/expiry policy on the users table.

## Decision
Add a new auth token issuance path (login/session touching), and a schema migration
for the new column.

## Tasks
- TASK-001: add the `reset_token` migration (schema change, retention policy)
- TASK-002: wire the login flow to issue + validate the token (auth, session)
