# How to Upload Screenshots to a PR

This guide covers how to commit screenshots to a branch, embed them in PR comments so they render correctly, and verify the result.

## 1. Commit screenshots to the branch

Use the naming convention `screenshots/{feature-name}/{NN}-{description}.png`:

```
screenshots/lobby-redirect/01-lobby-page-desktop.png
screenshots/lobby-redirect/02-brand-click-lobby.png
screenshots/lobby-redirect/03-lobby-page-mobile.png
```

Commit and push:

```bash
git add screenshots/
git commit -m "Add visual testing screenshots for [feature]"
git push
```

## 2. Use the correct image URL format

Relative paths like `![alt](screenshots/01-foo.png)` **do not work** in PR descriptions or comments — GitHub only resolves relative paths inside committed markdown files (e.g. READMEs).

Use the GitHub blob URL with `?raw=true`:

```markdown
![Description](https://github.com/<owner>/<repo>/blob/<branch>/screenshots/feature/01-screenshot.png?raw=true)
```

If you use `.patchboard/tooling/pr-screenshots.sh`, it builds the correct URL for the current repository automatically.

> **Why not `raw.githubusercontent.com`?** That domain does not carry GitHub session cookies, so images from **private repos** return 404. The `blob/...?raw=true` pattern works because it goes through `github.com`, where the viewer is already authenticated.

### User-uploaded images

If you upload images via the GitHub UI (drag-and-drop), GitHub generates a `user-attachments` URL. These must also use image syntax to embed:

```markdown
<!-- Broken — renders as a clickable link, not an image -->
https://github.com/user-attachments/assets/abc123...

<!-- Works — renders as an inline image -->
![Description](https://github.com/user-attachments/assets/abc123...)
```

## 3. Verify images render correctly

After posting a PR comment with images, verify that the URLs actually resolve — do not just check the markdown syntax.

### Check markdown syntax

```bash
gh pr view <PR_NUMBER> --comments --json comments --jq '.comments[-1].body'
```

### Check that each image URL returns HTTP 200

```bash
gh pr view <PR_NUMBER> --comments --json comments --jq '.comments[-1].body' \
  | grep -oP '!\[.*?\]\(\K[^)]+' \
  | while read url; do
      status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
      echo "$status $url"
    done
```

Verify:
- All screenshot links use `![alt](https://github.com/<owner>/<repo>/blob/<branch>/...?raw=true)` syntax
- No `raw.githubusercontent.com` URLs (these return 404 for private repos)
- No relative paths like `![alt](screenshots/...)` — these will not render
- Every URL returns HTTP 200 (or 302 redirect to the image)

If any images are broken, edit the comment to fix them before proceeding.
