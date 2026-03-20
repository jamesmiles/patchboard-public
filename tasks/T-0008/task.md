---
id: T-0008
title: "Write how to conduct visual testing"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on:
  - T-0004
  - T-0005
parallel_with: []
parent_epic: E-0001
acceptance:
  - "docs/faq/how-to-conduct-visual-testing.md documents the visual testing workflow for the project"
  - "@playwright/cli is the recommended default approach for agents"
  - "Installation instructions for @playwright/cli are documented"
  - "How to authenticate in the browser context is documented"
  - "The core workflow (navigate, snapshot, interact, verify, screenshot) is documented"
  - "Screenshot naming conventions and capture workflow are documented"
  - "How to verify page state before capturing screenshots is documented"
  - "Common DOM selectors or accessibility tree patterns for key UI elements are listed"
  - "Key @playwright/cli commands are documented with examples"
  - "How to attach findings to a task or PR is referenced"
  - "Troubleshooting common issues is included"
  - "The agent has exercised the documented instructions and confirmed they work"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

Visual testing captures screenshots to verify UI features work correctly. It provides visual evidence for PR reviews and catches integration bugs that unit tests miss. Agents need a clear, project-specific guide to navigate the application and capture meaningful screenshots.

Depends on T-0004 (local environment setup) and T-0005 (login) since the application must be running and authenticated before visual testing can begin.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse the project's UI framework and any existing test infrastructure (e.g. Playwright, Cypress, Selenium scripts or fixtures)
   - **If new**: ensure the user has provided sufficient context to describe the visual testing approach. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. If no visual testing support exists, default to `@playwright/cli` — create a Makefile target or script to install it:
   ```bash
   npm install -g @playwright/cli@latest
   ```
   If the global binary is unavailable, `npx playwright-cli` works as a fallback.
3. Document the `@playwright/cli` core workflow for the project. The standard pattern is:
   - **Navigate**: `playwright-cli goto <url>`
   - **Snapshot**: `playwright-cli snapshot` — returns an accessibility tree with element refs
   - **Interact**: `playwright-cli click <ref>`, `playwright-cli select <ref> "<value>"`, `playwright-cli fill <ref> "<text>"`
   - **Verify**: `playwright-cli snapshot` again to confirm the expected state
   - **Screenshot**: `playwright-cli screenshot --filename=<path>`
4. Document authentication in the browser context — opening a browser session and injecting auth cookies:
   ```bash
   playwright-cli open <app-url>
   playwright-cli cookie-set <cookie-name> "<token>" --domain=<domain>
   playwright-cli goto <app-url>
   ```
5. Document saving and restoring auth state to avoid repeated authentication:
   ```bash
   playwright-cli state-save auth-state.json
   playwright-cli state-load auth-state.json
   ```
6. Document the screenshot naming convention: `screenshots/{feature-name}/{NN}-{description}.png`
7. Document key `@playwright/cli` commands with project-specific examples:
   - **Navigation**: `goto`, `go-back`, `go-forward`
   - **Inspection**: `snapshot`, `screenshot`, `pdf`
   - **Interaction**: `click`, `dblclick`, `fill`, `select`, `check`, `uncheck`, `hover`, `drag`, `upload`
   - **State**: `cookie-set`, `cookie-list`, `state-save`, `state-load`
   - **Debugging**: `console`, `network`, `eval`
   - **Sessions**: `open`, `close`, `list`, `tab-list`, `tab-new`, `tab-select`, `resize`
   - **Recording**: `tracing-start`/`tracing-stop`, `video-start`/`video-stop`
   - **Dialogs**: `dialog-accept`, `dialog-dismiss`
8. Document key limitations:
   - Element refs change between snapshots — always re-snapshot after navigation or interaction
   - Matching is by accessible name, not HTML `id`
   - Sessions are in-memory by default; use `--persistent` with `open` to persist across browser restarts
9. Identify and document common DOM selectors or accessibility tree patterns for key UI elements in the project
10. Reference how to attach findings to tasks ([How to attach feedback to a task](/docs/faq/how-to-attach-feedback-to-a-task.md)) and PRs ([How to upload screenshots to a PR](/docs/faq/how-to-upload-screenshots-to-a-pr.md))
11. Add troubleshooting section
12. Follow the documented instructions end-to-end — install tooling, authenticate, navigate, capture a screenshot — and confirm each step works
13. Fix any inaccuracies found during verification
14. Remove the TODO placeholder

## Notes

If the project has no UI, this document should state that explicitly. For API-only projects, consider whether a similar guide for API testing would be more appropriate and note this for human review.

`@playwright/cli` is always the recommended default for agents even if existing scripted test suites exist, because it is faster, requires no script writing, and is more token-efficient. Scripted Playwright tests (Python/JS) should be documented as a secondary option for CI/CD or repeatable test suites only.
