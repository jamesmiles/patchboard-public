#!/usr/bin/env bash
#
# validate-agent-sync.sh - Check that .claude/agents/ and .patchboard/agents/ are in sync
#
# Each .claude/agents/<name>.md has a corresponding .patchboard/agents/<dir>/index.md.
# The body content (everything after the YAML frontmatter) must match between the two.
#
# The mapping from claude agent name to patchboard directory is:
#   - "pb-" prefix is stripped (pb-tester -> tester, pb-engineer -> engineer)
#   - Otherwise the name is used as-is (planner -> planner, qc-manager -> qc-manager)
#
# Usage: validate-agent-sync.sh [--fix]
#   --fix   Show a diff for each mismatch (does not auto-fix)
#
# Exit codes:
#   0 - All agents in sync
#   1 - One or more agents out of sync

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

CLAUDE_DIR="${REPO_ROOT}/.claude/agents"
PATCHBOARD_DIR="${REPO_ROOT}/.patchboard/agents"

SHOW_DIFF=false
if [[ "${1:-}" == "--fix" ]]; then
    SHOW_DIFF=true
fi

# Strip YAML frontmatter (everything between --- markers) and output the body
strip_frontmatter() {
    local file="$1"
    awk '
        BEGIN { in_frontmatter=0; found_end=0 }
        /^---\s*$/ {
            if (!in_frontmatter && !found_end) { in_frontmatter=1; next }
            if (in_frontmatter) { in_frontmatter=0; found_end=1; next }
        }
        !in_frontmatter && found_end { print }
    ' "$file"
}

errors=0
checked=0

for claude_file in "${CLAUDE_DIR}"/*.md; do
    [[ -e "$claude_file" ]] || continue

    # Extract agent name from filename
    agent_name="$(basename "$claude_file" .md)"

    # Map claude name to patchboard directory
    pb_name="${agent_name#pb-}"  # Strip pb- prefix if present

    pb_file="${PATCHBOARD_DIR}/${pb_name}/index.md"

    if [[ ! -f "$pb_file" ]]; then
        echo "MISSING  ${pb_file#$REPO_ROOT/}  (no patchboard index for ${agent_name})"
        errors=$((errors + 1))
        checked=$((checked + 1))
        continue
    fi

    # Compare body content (after frontmatter)
    claude_body="$(strip_frontmatter "$claude_file")"
    pb_body="$(strip_frontmatter "$pb_file")"

    if [[ "$claude_body" != "$pb_body" ]]; then
        echo "DRIFT    .claude/agents/${agent_name}.md  ≠  .patchboard/agents/${pb_name}/index.md"
        errors=$((errors + 1))

        if [[ "$SHOW_DIFF" == "true" ]]; then
            diff --color=auto -u \
                <(echo "$pb_body") \
                <(echo "$claude_body") \
                --label ".patchboard/agents/${pb_name}/index.md" \
                --label ".claude/agents/${agent_name}.md" \
            || true
            echo ""
        fi
    else
        echo "OK       .claude/agents/${agent_name}.md  =  .patchboard/agents/${pb_name}/index.md"
    fi

    checked=$((checked + 1))
done

echo ""
echo "${checked} agent(s) checked, ${errors} issue(s) found."

if [[ $errors -gt 0 ]]; then
    exit 1
fi

exit 0
