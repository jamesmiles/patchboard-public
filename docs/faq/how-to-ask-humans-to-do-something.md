# How to Ask Humans to Do Something

Sometimes agents hit a blocker that only a human can resolve — AWS access, purchasing decisions, design approvals, infrastructure provisioning, or anything that requires human judgement or credentials.

## Option 1: Ask directly (interactive sessions)

If you're running in an interactive session with a human, **just ask them**. This is always the fastest path.

Use your conversation tools (e.g., `AskUserQuestion` in Claude Code, or the chat interface in your environment) to explain what you need and why. The human can often resolve it immediately — running a command, granting access, making a decision — without any task overhead.

Examples:
- "I need an active AWS session to pull staging logs. Can you run `awsp login staging-readonly`?"
- "This PR needs a design decision: should we use polling or WebSockets? What do you prefer?"
- "The test database is missing seed data. Can you run `make qa-serve` in another terminal?"

If the human resolves it, carry on. No task needed.

## Option 2: Create a `human-action` task (async / unattended)

If you're running unattended (e.g., a cloud agent, CI job, or scheduled task), or the human can't resolve it right now, create a task with the `human-action` label. Commit it to a branch and open a PR so it's visible.

```yaml
---
id: T-XXXX
title: "Provision SES production access for transactional emails"
type: task
status: todo
priority: P1
owner: null
labels:
  - human-action
  - infra
depends_on: []
parent_epic: null
acceptance:
  - "SES account is out of sandbox mode in production"
created_at: 'YYYY-MM-DD'
updated_at: 'YYYY-MM-DD'
---

## Context

Agents cannot send magic link emails on staging because SES is in sandbox
mode. A human needs to request production SES access from AWS.

## Notes

This blocks T-XXXX (user authentication on staging).
```

Key points:
- Set `status: todo` — never assign yourself as owner
- Set `owner: null` or a specific human handle if you know who should do it
- Add the `human-action` label so it's filterable and visible on the board
- Add other relevant labels too (e.g., `infra`, `product`, `security`)
- Use `depends_on` to link the blocked task if applicable
- **Put the task in a PR** so it's reviewed and merged into the backlog

## When to create a human-action task

| Situation | Example |
|-----------|---------|
| **Access & credentials** | AWS account setup, API keys, SSO profiles |
| **Purchasing decisions** | Domain names, licences, third-party services |
| **Approvals** | Design sign-off, architecture review, security review |
| **Infrastructure** | DNS changes, certificate provisioning, environment setup |
| **Account provisioning** | Creating accounts on external services |
| **Judgement calls** | Choosing between approaches, prioritisation decisions |

## When NOT to create a task

- If you're in an interactive session — ask directly first (Option 1)
- If you just need information, check the FAQ and docs first
- If you need AWS access for an existing profile, see [How to access staging and production](how-to-access-deployment-environments.md) — the human may just need to run `awsp login`
- If you're blocked on another agent's work, use `depends_on` instead

## Referencing the request

After creating the task, mention it in your current work so the connection is clear:

```markdown
<!-- In your PR description or task notes -->
Blocked by T-XXXX (human-action: need SES production access)
```

## What happens next

1. The task appears on the board with the `human-action` label
2. A human picks it up, completes the action, and moves it to `done`
3. Your dependent task is unblocked and can proceed
