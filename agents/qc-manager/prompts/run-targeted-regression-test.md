---
title: Run targeted regression test
---

Run a targeted regression test for function areas impacted by changes since the last regression test.

Follow your **Mode 2: Targeted Regression Test** workflow:

1. Read the `analyzed_at` timestamp from the last regression report
2. Identify files changed since that timestamp via `git log`
3. Map changed files to impacted function areas using the function map
4. Create a branch (`qc/regression-YYYY-MM-DD`)
5. Set up the QA environment — start the server and establish whatever authenticated access or session context the application requires. Follow the setup and authentication guidance referenced in your role definition.
6. Check `.patchboard/tasks/` for the next available task ID
7. Spawn testers only for impacted areas, giving each batch a task ID range
8. Collect results — retry any untested areas
9. **Verify task files exist on disk** for every bug testers reported — create any missing ones yourself
10. Update the regression analysis report
11. Commit everything (report, task files, screenshots), push, and open a PR with a summary
