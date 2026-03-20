---
id: T-0005
title: "Write how to login to an environment"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on:
  - T-0004
parallel_with: []
parent_epic: E-0001
acceptance:
  - "docs/faq/how-to-login-to-an-environment.md documents the authentication method(s) used by the project"
  - "Local development authentication flow is documented step-by-step"
  - "How to use the resulting token/session in scripts, curl, and browser is documented"
  - "Remote/hosted environment authentication is documented (if applicable)"
  - "Troubleshooting common auth failures is included"
  - "The agent has exercised the documented instructions and confirmed they work"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

Agents need to authenticate before they can interact with the application — whether for visual testing, API calls, or verification. This guide covers how to log in locally and on remote environments.

Depends on T-0004 (local environment setup) since the application must be running before authentication can be attempted.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse the project's authentication implementation — identify the auth method (e.g. magic link, OAuth, API keys, username/password), relevant endpoints, and any token/session management
   - **If new**: ensure the user has provided sufficient context to describe the authentication flow. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Document the local development authentication flow step-by-step
3. Document how to use the resulting token/session in scripts (curl, Playwright, etc.)
4. Document remote/hosted environment authentication if applicable
5. Add troubleshooting for common auth failures
6. Follow the documented instructions end-to-end — authenticate locally, use the token in a script — and confirm each step works
7. Fix any inaccuracies found during verification
8. Remove the TODO placeholder

## Notes

If the project has no authentication, this document should state that explicitly so agents don't waste time looking for a login flow.
