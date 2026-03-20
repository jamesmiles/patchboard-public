---
title: Rescue Blocked PR
---

PR#{{PR_NUMBER}} ("{{TITLE}}") on branch `{{HEAD_REF}}` → `{{BASE_REF}}` is blocked.

Please investigate and fix whatever is preventing this PR from merging — this may include merge conflicts, failing CI checks, or both. Follow the guidelines in your role definition. After pushing fixes, monitor CI with `gh pr checks {{PR_NUMBER}} --watch` and repeat until the PR is ready to merge.
