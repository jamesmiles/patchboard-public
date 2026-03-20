---
title: Verify a PR for the Engineering Manager
---

Conduct independent verification of PR#{{PR_NUMBER}} against the acceptance criteria provided by the Engineering Manager.

**You are testing as a sub-agent of the Engineering Manager.** Your job is to verify the implementation independently — you were not involved in building it. Report your results back to the manager, who will decide next steps.

## Inputs

The Engineering Manager will provide:
- **PR number** and **branch name**
- **Task ID** (e.g., T-0095)
- **Acceptance criteria** — the specific requirements to verify

## Steps

1. **Review the acceptance criteria and create a test plan** — you already have the criteria from the manager. Now plan how to verify each one:

   - Which pages/routes to visit for each criterion
   - Which interactions to test (buttons, forms, modals, filters)
   - Expected outcomes for each criterion
   - Edge cases worth checking (empty states, error handling, boundary values)
   - Potential regressions — surrounding features that share code paths or UI components with the changed areas

   Optionally read the PR diff (`gh pr diff {{PR_NUMBER}}`) to understand the scope of code changes and inform your plan — but the acceptance criteria are your primary input.

   Write the test plan out in your response before proceeding.

2. **Set up the environment** — checkout the PR branch and start the server:

   ```bash
   gh pr checkout {{PR_NUMBER}}
   ```

   Then follow your role definition (index.md) for environment setup and authentication.

3. **Execute the test plan** — work through your plan systematically:

   - Navigate to each page/route identified in your plan
   - Verify expected elements and behaviour
   - Test the interactions listed in your plan
   - Capture screenshots as evidence (before/after where relevant)
   - Note any deviations from expected behaviour

4. **Attach findings to the task** — add your results to the associated task:

   Follow [How to attach feedback to a task](/docs/faq/how-to-attach-feedback-to-a-task.md) to add summary comments and screenshot artifacts to the associated task or epic.

5. **Report results to the manager** — structure your output so the manager can evaluate pass/fail:

   For each acceptance criterion, report:
   - **Criterion**: (the requirement text)
   - **Result**: PASS / FAIL
   - **Evidence**: screenshot file path(s)
   - **Notes**: any observations, deviations, or concerns

   Then summarise:
   - **Overall result**: pass / pass with notes / fail
   - **Bugs found**: description, severity, and reproduction steps for each
   - **Regression concerns**: any issues in surrounding features

   The manager uses this output to decide whether to proceed or loop back to the engineer for fixes. Be precise — vague results cause unnecessary rework cycles.
