#!/usr/bin/env bash
#
# validate-pr.sh - Validate PR quality gates (screenshots, embedded images, URL rendering)
#
# Usage: validate-pr.sh <PR_NUMBER> [--check screenshots] [--json]
#
# Checks that a PR has screenshots committed, embedded in comments with ![](...)
# syntax, and that image URLs actually return HTTP 200/302.
#
# Dependencies: gh, jq, curl

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
CHECK_FILTER=""
OUTPUT_JSON=false

usage() {
    cat <<'EOF'
Usage: validate-pr.sh <PR_NUMBER> [OPTIONS]

Validate PR quality gates.

Options:
  --check CHECK    Run a specific check (screenshots). Default: run all.
  --json           Output machine-readable JSON
  -h, --help       Show this help message

Checks:
  screenshots      Screenshots committed, embedded in PR comments, URLs render

Examples:
  validate-pr.sh 599                        # Run all checks
  validate-pr.sh 599 --check screenshots    # Only screenshot checks
  validate-pr.sh 599 --json                 # JSON output for scripting
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_FILTER="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON=true
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
            else
                echo "Unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$PR_NUMBER" ]]; then
    echo "Error: PR_NUMBER is required." >&2
    usage >&2
    exit 1
fi

check_prerequisites() {
    local missing=()
    for cmd in gh jq curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}" >&2
        exit 1
    fi
}

# Results accumulator
RESULTS="[]"
OVERALL="pass"

add_result() {
    local name="$1" status="$2" details="$3"
    RESULTS=$(echo "$RESULTS" | jq \
        --arg name "$name" \
        --arg status "$status" \
        --arg details "$details" \
        '. + [{"name": $name, "status": $status, "details": $details}]')
    if [[ "$status" == "fail" ]]; then
        OVERALL="fail"
    fi
}

print_result() {
    local name="$1" status="$2" details="$3"
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        return
    fi
    if [[ "$status" == "pass" ]]; then
        echo -e "  ${GREEN}PASS${NC} $name"
    else
        echo -e "  ${RED}FAIL${NC} $name"
    fi
    if [[ -n "$details" ]]; then
        echo -e "       ${details}"
    fi
}

# --- Screenshot checks ---

check_screenshots_committed() {
    local files
    files=$(gh pr diff "$PR_NUMBER" --name-only 2>/dev/null | grep -i screenshot || true)

    if [[ -n "$files" ]]; then
        local count
        count=$(echo "$files" | wc -l)
        print_result "Screenshots committed" "pass" "${count} screenshot file(s) in diff"
        add_result "screenshots_committed" "pass" "${count} screenshot file(s) in diff"
    else
        print_result "Screenshots committed" "fail" "No screenshot files found in PR diff"
        add_result "screenshots_committed" "fail" "No screenshot files found in PR diff"
    fi
}

check_screenshots_embedded() {
    local comments
    comments=$(gh pr view "$PR_NUMBER" --comments --json comments --jq '[.comments[].body] | map(select(test("!\\["))) | length' 2>/dev/null || echo "0")

    if [[ "$comments" -gt 0 ]]; then
        print_result "Screenshots embedded in comments" "pass" "${comments} comment(s) contain embedded images"
        add_result "screenshots_embedded" "pass" "${comments} comment(s) contain embedded images"
    else
        print_result "Screenshots embedded in comments" "fail" "No PR comments contain ![  image syntax"
        add_result "screenshots_embedded" "fail" "No PR comments contain embedded images"
    fi
}

check_screenshot_urls_render() {
    # Extract all image URLs from PR comments
    local urls
    urls=$(gh pr view "$PR_NUMBER" --comments --json comments --jq '[.comments[].body] | join("\n")' 2>/dev/null \
        | grep -oP '!\[.*?\]\(\K[^)]+' || true)

    if [[ -z "$urls" ]]; then
        print_result "Screenshot URLs render" "fail" "No image URLs found in PR comments"
        add_result "screenshots_render" "fail" "No image URLs found in PR comments"
        return
    fi

    # Get the PR branch for API verification
    local branch
    branch=$(gh pr view "$PR_NUMBER" --json headRefName -q .headRefName 2>/dev/null)
    local repo_nwo
    repo_nwo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)

    local total=0 ok=0 broken=0 broken_urls=""

    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        total=$((total + 1))

        # Extract file path from blob URL: .../blob/<branch>/<path>?raw=true
        local file_path
        file_path=$(echo "$url" | sed -n "s|.*github\.com/${repo_nwo}/blob/[^/]*/\(.*\)?raw=true|\1|p")

        if [[ -z "$file_path" ]]; then
            # Not a blob URL we can parse — try raw curl as fallback
            local status
            status=$(curl -sL -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
            if [[ "$status" == "200" || "$status" == "302" ]]; then
                ok=$((ok + 1))
            else
                broken=$((broken + 1))
                broken_urls="${broken_urls}\n       Not verifiable: ${url}"
            fi
            continue
        fi

        # Verify file exists on the branch via GitHub API (works for private repos)
        if gh api "repos/${repo_nwo}/contents/${file_path}?ref=${branch}" --jq '.name' &>/dev/null; then
            ok=$((ok + 1))
        else
            broken=$((broken + 1))
            broken_urls="${broken_urls}\n       Not found: ${file_path} (ref: ${branch})"
        fi
    done <<< "$urls"

    if [[ "$broken" -eq 0 ]]; then
        print_result "Screenshot URLs render" "pass" "${ok}/${total} image(s) verified via API"
        add_result "screenshots_render" "pass" "${ok}/${total} image(s) verified via API"
    else
        print_result "Screenshot URLs render" "fail" "${broken}/${total} image(s) not found${broken_urls}"
        add_result "screenshots_render" "fail" "${broken}/${total} image(s) not found"
    fi
}

run_screenshot_checks() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${BOLD}Screenshots${NC} (PR #${PR_NUMBER})"
    fi
    check_screenshots_committed
    check_screenshots_embedded
    check_screenshot_urls_render
}

# --- Main ---

main() {
    check_prerequisites

    if [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "screenshots" ]]; then
        run_screenshot_checks
    else
        echo "Unknown check: $CHECK_FILTER" >&2
        exit 1
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        jq -n \
            --argjson checks "$RESULTS" \
            --arg overall "$OVERALL" \
            '{"pr": "'"$PR_NUMBER"'", "checks": $checks, "overall": $overall}'
    else
        echo ""
        if [[ "$OVERALL" == "pass" ]]; then
            echo -e "${GREEN}${BOLD}Overall: PASS${NC}"
        else
            echo -e "${RED}${BOLD}Overall: FAIL${NC}"
        fi
    fi

    if [[ "$OVERALL" == "fail" ]]; then
        exit 1
    fi
}

main
