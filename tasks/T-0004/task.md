---
id: T-0004
title: "Write how to set up a local server environment"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on:
  - T-0002
parallel_with: []
parent_epic: E-0001
acceptance:
  - "docs/faq/how-to-setup-local-server-environment.md documents how to install dependencies"
  - "Database setup steps are documented (if applicable)"
  - "How to start the server/application locally is documented"
  - "Key environment variables are listed with their purpose and defaults"
  - "Common troubleshooting steps are included (e.g. port conflicts, missing dependencies)"
  - "The agent has exercised the documented instructions and confirmed they work"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

This is the foundational how-to guide. Agents cannot test, verify, or debug anything without a working local environment. Most other FAQ guides depend on this one.

Depends on T-0002 (architecture overview) to understand what components need to be running locally.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse the project's build system, package manager config, Makefile/scripts, Dockerfiles, and README for setup instructions
   - **If new**: ensure the user has provided sufficient context to describe the setup process. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Identify all dependencies: language runtimes, package managers, databases, external services
3. Identify how the server/application is started and on which port(s)
4. Identify key environment variables and their defaults
5. Write the guide in `docs/faq/how-to-setup-local-server-environment.md` covering: dependency installation, database setup (if applicable), starting the application, environment variables, and troubleshooting
6. Follow the documented instructions end-to-end — install dependencies, start any databases, start the application — and confirm each step works
7. Fix any inaccuracies found during verification
8. Remove the TODO placeholder

## Notes

The guide should be step-by-step and copy-pasteable — agents will follow it literally. Avoid vague instructions like "install the dependencies"; prefer explicit commands.
