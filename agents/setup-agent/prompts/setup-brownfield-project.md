---
title: Setup brownfield project
---

Set up Patchboard documentation for an existing project with source code already in the repository.

Since this is a brownfield project, you should be able to derive most documentation by analysing the existing codebase, configuration, and infrastructure. Work through the setup epic (E-0001) tasks in order.

## Additional context from the project owner (optional)

<!-- ============================================================
     PROJECT OWNER: Optionally add context that cannot easily be
     derived from the source code. This might include:

     - Business context or product vision not evident from code
     - Deployment credentials or access patterns
     - Team conventions or preferences
     - Known quirks or gotchas
     - Links to external documentation or wikis

     If you leave this section empty, the agent will analyse the
     repository and derive what it can. It will ask for help when
     it encounters gaps it cannot fill from the codebase alone.
     ============================================================ -->

No additional context provided. The agent will analyse the repository.

## Workflow

1. Read the setup epic: `tasks/E-0001/task.md`
2. For each child task in order:
   - Read the task and its plan
   - Analyse the existing source code, configuration files, infrastructure code, CI/CD pipelines, README, and any other artefacts to derive the content
   - If you encounter gaps that cannot be filled from the codebase, escalate using [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
   - Write the document
   - For how-to guides: exercise every documented step end-to-end and confirm it works
   - Deliver each task as a separate PR
3. Update task status as you progress
