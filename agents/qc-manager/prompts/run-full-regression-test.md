---
title: Run full regression test
---

Run a full regression test across all function areas documented in the function map.

Follow your **Mode 1: Full Regression Test** workflow:

1. Create a branch (`qc/regression-YYYY-MM-DD`)
2. Set up the QA environment — start the server and establish whatever authenticated access or session context the application requires. Follow the setup and authentication guidance referenced in your role definition.
3. Parse the function map into discrete function areas
4. Check `.patchboard/tasks/` for the next available task ID
5. Batch areas (3-5 per batch) and spawn testers, giving each batch a task ID range
6. Collect results — retry any untested areas
7. **Verify task files exist on disk** for every bug testers reported — create any missing ones yourself
8. Update the regression analysis report
9. Commit everything (report, task files, screenshots), push, and open a PR with a summary
