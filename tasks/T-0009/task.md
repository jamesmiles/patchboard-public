---
id: T-0009
title: "Write how to verify task implementation"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on:
  - T-0008
parallel_with: []
parent_epic: E-0001
acceptance:
  - "docs/faq/how-to-verify-task-implementation.md documents the self-verification workflow for engineers"
  - "When to use this guide is clearly stated (after implementation, before review)"
  - "How to review acceptance criteria before starting verification is documented"
  - "How to start a verification-ready local environment is documented"
  - "How to authenticate for verification is documented"
  - "How to systematically verify each acceptance criterion with screenshot evidence is documented"
  - "How to run relevant project tests as part of verification is documented"
  - "How to post evidence to the PR is documented"
  - "Rules for verification are listed (e.g. every criterion must have evidence)"
  - "Handoff guidance for reviewers is included"
  - "The agent has exercised the documented instructions and confirmed they work"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

This guide covers the engineer self-verification workflow — the step between finishing implementation and handing work to reviewers. It ensures every acceptance criterion has been tested and has visual or test evidence before a PR is considered ready for review.

Depends on T-0008 (visual testing) since verification relies on screenshot capture and browser automation.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse the project's test infrastructure, CI/CD checks, and any existing verification patterns or scripts
   - **If new**: ensure the user has provided sufficient context to describe the verification workflow. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Document the verification workflow step-by-step:
   - **Review acceptance criteria** — work from the actual task or epic file, decide what page/flow proves each criterion, what counts as a pass, and what screenshot captures the evidence
   - **Start a verification-ready local environment** — reference the environment setup guide, document any QA-specific seed data or configuration (e.g. running on an alternate port to avoid conflicts)
   - **Authenticate** — reference the login guide
   - **Verify each criterion** — navigate, confirm expected state, interact, capture screenshot, note pass/fail
   - **Run relevant project tests** — identify the right test commands from the project's README or test infrastructure, run the most relevant subset for the areas changed
   - **Post evidence to the PR** — commit screenshots, post a PR comment with inline image embeds referencing [How to upload screenshots to a PR](/docs/faq/how-to-upload-screenshots-to-a-pr.md)
3. Document the verification rules:
   - Do not skip any acceptance criterion
   - Every criterion must have a screenshot or explicit pass/fail note in the PR evidence
   - Screenshots must be embedded inline in a PR comment, not just raw links
   - If blocked, follow [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
4. Document the handoff — what reviewers should see in the PR comment: which criteria were checked, which screenshots map to which criteria, any known limitations or follow-up notes
5. Follow the documented instructions end-to-end and confirm each step works
6. Fix any inaccuracies found during verification
7. Remove the TODO placeholder

## Notes

This guide is specifically for engineer self-verification. Independent testing by a separate tester agent is a different phase and should not be conflated with this workflow.
