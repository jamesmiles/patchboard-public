---
id: T-0001
title: "Write product vision document"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on: []
parallel_with: []
parent_epic: E-0001
acceptance:
  - "docs/product/vision.md contains a project vision document"
  - "Background section explains why the project exists and what problem it solves"
  - "Mission statement is defined"
  - "Vision section describes the desired future state"
  - "Unique selling proposition (USP) or key differentiators are articulated"
  - "Value creation is described — who benefits and how (e.g. for users, teams, stakeholders)"
  - "Target audience is identified"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

A product vision document gives agents and contributors the "why" behind the project. Without it, agents lack the high-level context needed to make informed decisions when planning, implementing, or reviewing work.

This is the first task in the Setup Patchboard epic (E-0001) because the vision sets the foundation that all other documentation builds on.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse the project source code, README, and other artefacts in depth — identify the project's purpose, domain, and target audience
   - **If new**: ensure the user has provided sufficient context to write a vision. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Review any existing documentation, marketing materials, or stakeholder-facing content for vision cues
3. Write the product vision in `docs/product/vision.md` covering: background, mission, vision, USP/differentiators, value creation, and target audience
4. Remove the TODO placeholder

## Notes

For existing projects, an agent can analyse the project source code, README, and other artefacts to derive much of the vision. For new projects, additional human input is more likely required.
