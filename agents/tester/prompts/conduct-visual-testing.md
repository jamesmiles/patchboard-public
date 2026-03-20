---
title: Visual test a PR
---

Conduct visual testing of PR#{{PR_NUMBER}}. Verify UI functionality, capture screenshots of changed areas, and report findings.

## Steps

1. **Establish scope** — understand what the PR is implementing and why:

   ```bash
   gh pr view {{PR_NUMBER}}
   gh pr diff {{PR_NUMBER}}
   ```

   - Read the **full diff** to understand what the code actually changes — not just which files, but what behaviour is being added or modified.
   - The diff will include changes to **task files** (`.patchboard/tasks/T-NNNN/task.md`) — the engineer updates their status as part of the PR. These tell you which tasks are being worked on.
   - Read those task files to understand the feature intent and **acceptance criteria**.
   - Identify which UI areas are directly affected and which **surrounding features** could be impacted by the changes.

2. **Create a test plan** — based on the acceptance criteria and changed files, list what you will verify:

   - Which pages/routes to visit
   - Which interactions to test (buttons, forms, modals, filters)
   - Expected outcomes for each (derived from acceptance criteria)
   - Edge cases worth checking (empty states, error handling, boundary values)
   - Potential regressions — surrounding features that share code paths or UI components with the changed areas

   Write the test plan out in your response before proceeding.

3. **Set up the environment** — checkout the PR branch and start the server:

   ```bash
   gh pr checkout {{PR_NUMBER}}
   ```

   Then follow your role definition (index.md) for environment setup and authentication.

4. **Execute the test plan** — work through your plan systematically:

   - Navigate to each page/route identified in your plan
   - Verify expected elements and behaviour
   - Test the interactions listed in your plan
   - Capture screenshots as evidence (before/after where relevant)
   - Note any deviations from expected behaviour

5. **Attach findings to tasks** — for each associated task or epic, add your results:

   Follow [How to attach feedback to a task](/docs/faq/how-to-attach-feedback-to-a-task.md) to add summary comments and screenshot artifacts to the associated task or epic.

6. **Post a summary comment on the PR** with:

   - Overall result (pass / pass with notes / fail)
   - Summary of findings against the test plan
   - Links to the tasks where screenshots were attached
   - Any UI improvement suggestions

   Follow [How to upload screenshots to a PR](/docs/faq/how-to-upload-screenshots-to-a-pr.md) for committing screenshots and verifying image URLs return HTTP 200.

7. **Monitor CI** — check that CI checks pass (do not re-run them yourself):

   ```bash
   gh pr checks {{PR_NUMBER}} --watch
   ```

   If a CI check fails, note it in your PR comment but do not attempt to fix it.
