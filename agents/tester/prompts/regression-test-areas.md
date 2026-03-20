---
title: Regression test function areas
---

Conduct regression testing of the assigned function areas. Compare current UI state against the baseline function map and report any changes.

**You are testing for the QC Manager.** Your job is to plan your testing, execute it, create git-tracked bug task files for any issues found (see step 4), and report results back.

## Inputs

The QC Manager will provide:
- **Function areas to test** — routes and expected elements/flows
- **Base URL and auth/session context** — pre-configured environment
- **Screenshot directory** — where to save evidence
- **Next task ID** — the next available T-NNNN ID for filing bugs

## Steps

1. **Review the baseline and plan your testing** — before opening a browser, study the function areas you've been assigned:

   - Read the expected elements and flows provided by the QC Manager
   - For each area, identify the **key interactions to verify** (not just page loads — buttons, forms, filters, navigation flows)
   - Note any **edge cases** relevant to each area (empty states, missing data, permission boundaries)
   - Mentally sequence your testing to minimise unnecessary navigation

2. **Set up the browser** — use the provided base URL and auth/session context. Use named sessions (`-s=batchN`) with `--persistent` to preserve browser state across navigations:

   ```bash
   playwright-cli -s=batchN open {{BASE_URL}} --persistent
   ```

   Then apply the provided authentication/session setup using the project's documented login or visual testing flow.

3. **Test each function area** — for each route/flow assigned:

   - Navigate to the route using any required project/workspace/tenant context for that area
   - Take a snapshot and verify expected elements are present
   - Interact with key controls (buttons, filters, modals) and verify behaviour
   - Capture screenshots as evidence
   - Compare against the expected baseline provided by the QC Manager
   - Note any deviations: missing elements, changed behaviour, new elements, broken interactions

4. **Create bug task files** (in `.patchboard/tasks/`) — for any breaking or significant issues, create a git-tracked task file. The frontmatter schema is defined in `.patchboard/schemas/task.schema.json`. Use the next available task ID provided by the QC Manager, incrementing for each additional bug.

   ```bash
   mkdir -p .patchboard/tasks/T-NNNN
   ```

   Then write `.patchboard/tasks/T-NNNN/task.md` with this format:

   ```markdown
   ---
   id: T-NNNN
   title: "Short description of the bug"
   type: bug
   status: todo
   priority: P1
   owner: null
   labels: [regression]
   depends_on: []
   parallel_with: []
   parent_epic: null
   acceptance:
     - "What 'fixed' looks like"
   created_at: "YYYY-MM-DD"
   updated_at: "YYYY-MM-DD"
   ---

   ## Context

   Discovered during regression test YYYY-MM-DD.

   ### Reproduction Steps

   1. Navigate to ...
   2. ...
   3. Result: ...

   ## Notes

   - Screenshot evidence: screenshots/regression-batchN/NN-description.png
   ```

   **Do NOT create tasks via the API** (`curl POST /api/tasks`). The API database is ephemeral. Only git-tracked task files in `.patchboard/tasks/` persist.

5. **Report results** — for each area tested, report:

   - **Status**: PASS / FAIL / CHANGED
   - **Elements found**: key elements verified
   - **Changes from baseline**: any differences from expected behaviour
   - **Bug tasks created**: task IDs and file paths for any issues filed
   - **Screenshots**: file paths of captured evidence

   The QC Manager reads your output directly — be concise and structured so it can aggregate results across batches.

## Rules

- **Verify required context before reporting bugs** — if a page shows "not found", empty state, or access errors, confirm the expected project/workspace/tenant/session context is set first
- **Create bug task files for breaking issues** — the QC Manager expects you to file git-tracked task files, not API tasks
- **Use severity labels** — P1 for breaking, P2 for significant UX issues, P3 for cosmetic
