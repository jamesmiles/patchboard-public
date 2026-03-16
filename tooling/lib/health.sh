#!/usr/bin/env bash
#
# health.sh - Healthcheck functions for patchboard
#
# Requires: REPO_ROOT, SCRIPT_DIR set by caller
# Requires: lib/colors.sh sourced

# ─── Schema validation ────────────────────────────────────────────

healthcheck_schema() {
    log_info "Schema validation..."

    if [[ -f "${SCRIPT_DIR}/patchboard.py" ]]; then
        local output
        output=$("${REPO_ROOT}/.venv/bin/python" "${SCRIPT_DIR}/patchboard.py" validate --verbose 2>&1) && {
            log_good "Schema validation passed"
            return 0
        } || {
            log_bad "Schema validation failed"
            echo "$output" | head -20 | while IFS= read -r line; do
                echo -e "    ${DIM}${line}${NC}"
            done
            return 1
        }
    else
        log_warn "patchboard.py not found — skipping schema validation"
        return 0
    fi
}

# ─── Git connectivity ─────────────────────────────────────────────

healthcheck_git() {
    log_info "Git connectivity..."

    # Check basic git
    if ! command -v git &>/dev/null; then
        log_bad "git not found"
        return 1
    fi

    # Check remote URL
    local remote_url
    remote_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)
    if [[ -z "$remote_url" ]]; then
        log_bad "No git remote 'origin' configured"
        return 1
    fi
    log_dim "Remote: ${remote_url}"

    # Test fetch (read access)
    log_dim "Testing fetch access..."
    if ! git -C "$REPO_ROOT" fetch --dry-run origin 2>/dev/null; then
        log_bad "Git fetch failed — check credentials/network"
        return 1
    fi
    log_good "Fetch access OK"

    # Test push (write access) — create and delete a probe branch
    log_dim "Testing push access..."
    local probe_branch="patchboard-healthcheck-$(date +%s)-${RANDOM}"

    # Create a lightweight ref pointing to HEAD
    local head_sha
    head_sha=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)

    if git -C "$REPO_ROOT" push origin "${head_sha}:refs/heads/${probe_branch}" --quiet 2>/dev/null; then
        # Clean up immediately
        git -C "$REPO_ROOT" push origin --delete "${probe_branch}" --quiet 2>/dev/null || true
        log_good "Push access OK"
    else
        log_bad "Git push failed — check write permissions"
        return 1
    fi

    log_good "Git connectivity OK"
    return 0
}

# ─── Claude CLI ───────────────────────────────────────────────────

healthcheck_claude() {
    log_info "Claude CLI..."

    if ! command -v claude &>/dev/null; then
        log_bad "Claude CLI not found"
        log_dim "Install: https://docs.anthropic.com/en/docs/claude-cli"
        return 1
    fi

    # Version
    local version
    version=$(claude --version 2>/dev/null | head -1)
    log_good "Installed: ${version}"

    # Auth check — claude doctor or a lightweight test
    log_dim "Checking authentication..."
    local auth_output
    auth_output=$(claude --print "hello" --output-format text 2>&1)
    local auth_rc=$?

    if [[ $auth_rc -eq 0 ]]; then
        log_good "Claude CLI authenticated"
    else
        log_bad "Claude CLI not authenticated or API error"
        echo "$auth_output" | head -5 | while IFS= read -r line; do
            echo -e "    ${DIM}${line}${NC}"
        done
        return 1
    fi

    return 0
}

# ─── Copilot CLI ──────────────────────────────────────────────────

healthcheck_copilot() {
    log_info "Copilot CLI..."

    if ! command -v copilot &>/dev/null; then
        log_warn "Copilot CLI not found (optional)"
        log_dim "Install: https://githubnext.com/projects/copilot-cli"
        return 0  # Not a failure — copilot is optional
    fi

    # Version
    local version
    version=$(copilot --version 2>/dev/null | head -1)
    log_good "Installed: ${version}"

    # Auth — check if gh is authenticated (copilot uses GitHub auth)
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            log_good "GitHub authentication OK (gh auth)"
        else
            log_warn "GitHub not authenticated — copilot may not work"
            log_dim "Run: gh auth login"
        fi
    fi

    return 0
}

# ─── Prerequisites ────────────────────────────────────────────────

healthcheck_prereqs() {
    log_info "Prerequisites..."
    local ok=true

    for cmd in jq git; do
        if command -v "$cmd" &>/dev/null; then
            log_good "${cmd} found"
        else
            log_bad "${cmd} not found"
            ok=false
        fi
    done

    # Optional tools
    for cmd in gh gzip; do
        if command -v "$cmd" &>/dev/null; then
            log_good "${cmd} found"
        else
            log_warn "${cmd} not found (optional)"
        fi
    done

    $ok
}

# ─── Run all healthchecks ────────────────────────────────────────

run_healthcheck() {
    local failures=0

    print_section "Prerequisites"
    healthcheck_prereqs || (( failures++ ))

    print_section "Schema Validation"
    healthcheck_schema || (( failures++ ))

    print_section "Git Connectivity"
    healthcheck_git || (( failures++ ))

    print_section "Claude CLI"
    healthcheck_claude || (( failures++ ))

    print_section "Copilot CLI"
    healthcheck_copilot || (( failures++ ))

    echo ""
    if [[ $failures -eq 0 ]]; then
        log_good "All healthchecks passed"
    else
        log_bad "${failures} healthcheck(s) failed"
    fi

    return $failures
}
