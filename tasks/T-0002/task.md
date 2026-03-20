---
id: T-0002
title: "Write architecture overview"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on: []
parallel_with:
  - T-0001
parent_epic: E-0001
acceptance:
  - "docs/technical/architecture.md describes the system's high-level architecture"
  - "System context is documented — primary actors and external systems"
  - "Key components/modules, their responsibilities, and how they interact are documented"
  - "Data flow is illustrated for key scenarios (e.g. how a typical request or workflow moves through the system)"
  - "Security model is documented — authentication, authorization, and secrets management"
  - "Operational considerations are documented — concurrency, reliability, and monitoring"
  - "Key design decisions are listed or linked to ADRs (if any exist)"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

The architecture overview is the canonical reference for how the system is structured. Agents need this to understand component boundaries, data flow, and technical constraints when planning or implementing work.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse the project source code in depth — identify key components, modules, services, and system design patterns
   - **If new**: ensure the user has provided sufficient context to describe the architecture. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Review configuration files, dependencies, and directory structure for technology choices and boundaries
3. Write the architecture overview in `docs/technical/architecture.md` covering: system context (actors, external systems), core components/modules, data flow scenarios, security model, operational considerations, and key design decisions
4. Include diagrams where helpful (Graphviz DOT supported)
5. Remove the TODO placeholder

## Notes

For existing projects, an agent can analyse the project source code, directory structure, configuration files, and dependencies to derive much of the architecture. For new projects, additional human input is more likely required.
