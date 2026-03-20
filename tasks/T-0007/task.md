---
id: T-0007
title: "Write how to access system logs"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on:
  - T-0004
  - T-0006
parallel_with: []
parent_epic: E-0001
acceptance:
  - "docs/faq/how-to-access-system-logs.md documents how to view logs in local development"
  - "Log file locations and console output behaviour are documented"
  - "How to control log verbosity/level is documented"
  - "How to access logs in remote/hosted environments is documented (if applicable)"
  - "How to search and filter logs is documented"
  - "Common log patterns and what to search for are listed (e.g. startup, errors, auth failures)"
  - "Relevant environment variables are listed"
  - "The agent has exercised the documented instructions and confirmed they work"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

Agents need to access logs for debugging, incident diagnosis, and verifying that operations completed successfully. This guide covers both local and remote log access.

Depends on T-0004 (local environment setup) for local logs and T-0006 (deployment environment access) for remote logs.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse the project's logging configuration — identify log frameworks, output destinations (console, files, cloud services), log levels, and format options
   - **If new**: ensure the user has provided sufficient context to describe the logging setup. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Document local log access: console output, log file locations, how to tail logs
3. Document how to control log level and format
4. Document remote log access (e.g. CloudWatch, Datadog, ELK) referencing the deployment environment access guide where needed
5. Document common log patterns and search strategies
6. List relevant environment variables
7. Follow the documented instructions end-to-end — view local logs, change log level, search for a pattern — and confirm each step works
8. Fix any inaccuracies found during verification
9. Remove the TODO placeholder

## Notes

Remote log access may depend on the access patterns documented in T-0006. If remote environments are not yet accessible to agents, document what is known and note the gaps.
