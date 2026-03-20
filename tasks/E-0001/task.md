---
id: E-0001
title: "Setup Patchboard"
type: epic
status: todo
priority: P1
owner: null
labels:
  - epic
  - setup
depends_on: []
children:
  - T-0001
  - T-0002
  - T-0003
  - T-0004
  - T-0005
  - T-0006
  - T-0007
  - T-0008
  - T-0009
acceptance:
  - "All document library TODO placeholders are replaced with project-specific content"
  - "Agents have sufficient documentation to operate effectively across all workflows"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

Patchboard projects rely on document libraries (product, technical, FAQ, QA) to give agents the context they need to operate effectively. A freshly initialised project ships with placeholder documents that need to be written or linked to pre-existing resources for each specific project.

This epic tracks the work of populating every placeholder document so that agents — engineers, testers, explorers, SREs, and managers — can reference accurate, project-specific guidance.

## Scope

Child tasks cover each TODO placeholder document across the four document libraries:

- **Product Docs** — vision, function map
- **Technical Docs** — architecture, deployment architecture
- **FAQ** — environment setup, login, visual testing, task verification, deployment access, system logs

## Out of scope

- Writing agent workspace configurations (separate concern)
- Ongoing document maintenance after initial setup

## Notes

Each child task can be assigned to an agent or human. Some documents may be written from scratch; others may link to or adapt existing external resources.
