# How to Attach Feedback to a Task

When a task is in `review` status and the implementation PR is still open, you can attach comments and artifacts (screenshots, logs, test reports) directly to the task on the filesystem. This is the preferred way to leave feedback because:

- **Findings stay with the backlog item** rather than getting lost in branch history
- **Multiple agents or sessions** can contribute feedback to the same task
- **The UI** displays comments and artifacts inline on the task detail page

## 1. Add a comment

Create a Markdown file in the task's `comments/` directory. Comments use sequential IDs (`c-001`, `c-002`, etc.) and have YAML frontmatter with `id`, `author`, and `created_at`.

First, check what comments already exist to pick the next ID:

```bash
ls .patchboard/tasks/T-0095/comments/
# c-001.md  c-002.md
# → next comment is c-003
```

Then create the comment file:

```markdown
---
id: c-003
author: Tester
created_at: '2026-03-01T10:30:00+00:00'
---

## Visual Test Results

- Dashboard: OK
- Settings: 1 issue found — the sidebar collapses on narrow viewports
```

If the `comments/` directory doesn't exist yet, create it:

```bash
mkdir -p .patchboard/tasks/T-0095/comments
```

## 2. Add an artifact

Copy the file (screenshot, log, etc.) into the task's `artifacts/` directory, then add an entry to `manifest.json`.

```bash
# Create the artifacts directory if it doesn't exist
mkdir -p .patchboard/tasks/T-0095/artifacts

# Copy the file
cp screenshots/01-dashboard.png .patchboard/tasks/T-0095/artifacts/
```

Then create or update `manifest.json` — this is a JSON array of metadata objects:

```json
[
  {
    "filename": "01-dashboard.png",
    "uploaded_by": "Tester",
    "uploaded_at": "2026-03-01T10:30:00+00:00",
    "description": "Dashboard after login",
    "size": 38298,
    "content_type": "image/png"
  }
]
```

If `manifest.json` already exists, append your entry to the existing array.

| Field | Description |
|-------|-------------|
| `filename` | Must match the actual filename in the `artifacts/` directory |
| `uploaded_by` | Your agent name or human name |
| `uploaded_at` | ISO 8601 timestamp |
| `description` | Brief description of what the artifact shows |
| `size` | File size in bytes |
| `content_type` | MIME type (e.g., `image/png`, `text/plain`, `application/pdf`) |

## 3. Commit your feedback

Add the comments and artifacts to git and commit them, either to the existing PR branch or as part of a new commit:

```bash
git add .patchboard/tasks/T-0095/comments/ .patchboard/tasks/T-0095/artifacts/
git commit -m "Add visual test feedback to T-0095"
git push
```

## 4. Summarise on the PR

Leave a comment on the implementation PR so the author sees your findings without having to dig through task files:

```bash
gh pr comment 123 --body "## Review feedback for T-0095

- 2 comments added to T-0095
- 1 screenshot attached (dashboard after login)
- 1 issue found: sidebar collapses on narrow viewports

See \`.patchboard/tasks/T-0095/comments/\` for details."
```

Keep the PR comment short — it's a summary pointing to the detailed feedback on the task, not a duplicate of it.

## Directory structure

```
.patchboard/tasks/T-0095/
├── task.md                    # Task definition
├── comments/
│   ├── c-001.md              # Sequential comment files
│   ├── c-002.md
│   └── c-003.md
└── artifacts/
    ├── manifest.json         # Array of artifact metadata
    ├── 01-dashboard.png      # Uploaded files
    └── 02-settings-bug.png
```

Both tasks and epics support comments and artifacts — use the task ID or epic ID interchangeably.
