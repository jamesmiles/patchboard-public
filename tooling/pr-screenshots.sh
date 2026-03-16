#!/usr/bin/env bash
#
# pr-screenshots.sh - Commit screenshots and post them as embedded images on a PR
#
# Usage: pr-screenshots.sh <PR_NUMBER> <screenshot_dir> [--title "..."] [--no-commit]
#
# Automates: git add + commit + push screenshots, build markdown with blob URLs,
# post PR comment, verify URLs render.
#
# Dependencies: gh, git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# Defaults
PR_NUMBER=""
SCREENSHOT_DIR=""
TITLE="Verification Screenshots"
NO_COMMIT=false

usage() {
    cat <<'EOF'
Usage: pr-screenshots.sh <PR_NUMBER> <screenshot_dir> [OPTIONS]

Commit screenshots and post them as embedded images on a PR comment.

Arguments:
  PR_NUMBER        The PR number to post screenshots to
  screenshot_dir   Directory containing .png screenshot files (relative to repo root)

Options:
  --title TEXT     Comment title (default: "Verification Screenshots")
  --no-commit      Skip git add/commit/push (screenshots already committed)
  -h, --help       Show this help message

Examples:
  pr-screenshots.sh 599 screenshots/T-0288-testing/
  pr-screenshots.sh 599 screenshots/feature/ --title "Feature Screenshots"
  pr-screenshots.sh 599 screenshots/feature/ --no-commit
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --no-commit)
            NO_COMMIT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -z "$PR_NUMBER" ]]; then
                PR_NUMBER="$1"
            elif [[ -z "$SCREENSHOT_DIR" ]]; then
                SCREENSHOT_DIR="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$PR_NUMBER" || -z "$SCREENSHOT_DIR" ]]; then
    echo "Error: PR_NUMBER and screenshot_dir are required." >&2
    usage >&2
    exit 1
fi

check_prerequisites() {
    local missing=()
    for cmd in gh git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}" >&2
        exit 1
    fi
}

main() {
    check_prerequisites

    # Resolve screenshot dir relative to repo root
    local abs_dir="${REPO_ROOT}/${SCREENSHOT_DIR}"
    abs_dir="${abs_dir%/}"  # strip trailing slash

    if [[ ! -d "$abs_dir" ]]; then
        echo -e "${RED}Error: Directory not found: ${SCREENSHOT_DIR}${NC}" >&2
        exit 1
    fi

    # Find png files
    local -a png_files=()
    while IFS= read -r -d '' f; do
        png_files+=("$f")
    done < <(find "$abs_dir" -name '*.png' -print0 | sort -z)

    if [[ ${#png_files[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No .png files found in ${SCREENSHOT_DIR}${NC}" >&2
        exit 1
    fi

    echo -e "${BOLD}Found ${#png_files[@]} screenshot(s)${NC}"

    # Get branch name from PR
    local branch
    branch=$(gh pr view "$PR_NUMBER" --json headRefName -q .headRefName)
    echo -e "Branch: ${branch}"

    # Get repo owner/name
    local repo_nwo
    repo_nwo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

    # Commit and push if needed
    if [[ "$NO_COMMIT" != "true" ]]; then
        echo -e "\n${BOLD}Committing screenshots...${NC}"
        cd "$REPO_ROOT"
        git add "$SCREENSHOT_DIR"
        if git diff --cached --quiet; then
            echo -e "${YELLOW}No new changes to commit (screenshots already committed)${NC}"
        else
            git commit -m "Add verification screenshots"
            git push
            echo -e "${GREEN}Pushed screenshots to ${branch}${NC}"
        fi
    fi

    # Build markdown comment
    local body="## ${TITLE}\n\n"
    for f in "${png_files[@]}"; do
        local rel_path="${f#${REPO_ROOT}/}"
        local filename
        filename=$(basename "$f" .png)
        # Clean up filename for alt text: replace dashes/underscores with spaces
        local alt_text="${filename//-/ }"
        alt_text="${alt_text//_/ }"
        body+="### ${alt_text}\n"
        body+="![${alt_text}](https://github.com/${repo_nwo}/blob/${branch}/${rel_path}?raw=true)\n\n"
    done

    # Post PR comment
    echo -e "\n${BOLD}Posting PR comment...${NC}"
    gh pr comment "$PR_NUMBER" --body "$(echo -e "$body")"
    echo -e "${GREEN}Comment posted on PR #${PR_NUMBER}${NC}"

    # Verify files exist on remote via GitHub API (curl returns 404 for private repos)
    echo -e "\n${BOLD}Verifying screenshots exist on remote...${NC}"
    local total=0 ok=0 broken=0
    for f in "${png_files[@]}"; do
        local rel_path="${f#${REPO_ROOT}/}"
        total=$((total + 1))
        if gh api "repos/${repo_nwo}/contents/${rel_path}?ref=${branch}" --jq '.name' &>/dev/null; then
            ok=$((ok + 1))
            echo -e "  ${GREEN}OK${NC} ${rel_path}"
        else
            broken=$((broken + 1))
            echo -e "  ${RED}NOT FOUND${NC} ${rel_path}"
        fi
    done

    echo ""
    if [[ "$broken" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All ${total} screenshots verified on remote${NC}"
    else
        echo -e "${RED}${BOLD}${broken}/${total} screenshots not found on remote${NC}"
        exit 1
    fi
}

main
