#!/usr/bin/env bash
#
# agent.sh - Agent invocation, claiming, and post-run logic
#
# Agent invocation, claiming, and post-run logic.
#
# Requires: REPO_ROOT, SESSION_DIR, SCRIPT_DIR set by caller
# Requires: lib/colors.sh, lib/config.sh, lib/sessions.sh sourced

# ─── State ─────────────────────────────────────────────────────────
AGENT_CONV_ID=""
AGENT_TIMEOUT="${AGENT_TIMEOUT:-86400}"
AGENT_NON_INTERACTIVE="${AGENT_NON_INTERACTIVE:-true}"

runtime_session_subdir() {
    local session_id="$1"
    local runtime_dir="${SCRIPT_DIR}/state/cloud-agents/${session_id}"
    mkdir -p "$runtime_dir"
    echo "$runtime_dir"
}

# ─── UUID generation ───────────────────────────────────────────────

generate_uuid() {
    uuidgen 2>/dev/null \
        || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null \
        || cat /proc/sys/kernel/random/uuid 2>/dev/null \
        || echo "$(date +%s)-$$-${RANDOM}"
}

# ─── Branch management ─────────────────────────────────────────────

ensure_on_default_branch() {
    local default_branch
    if ! default_branch=$(config_resolve_branch); then
        return 1
    fi

    local current
    current=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

    if [[ "$current" != "$default_branch" ]]; then
        log_info "Switching from '${current}' to ${default_branch}..."
        if ! git -C "$REPO_ROOT" checkout "$default_branch" --quiet 2>/dev/null; then
            log_bad "Failed to switch to configured default branch '${default_branch}'."
            return 1
        fi
    fi
}

pull_latest_with_warning() {
    local context="$1"
    local pull_output=""
    if ! pull_output=$(git -C "$REPO_ROOT" pull --rebase --quiet 2>&1); then
        pull_output=$(printf '%s' "$pull_output" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//; s/ *$//')
        if [[ -n "$pull_output" ]]; then
            log_warn "${context} Failed to pull latest changes. Reason: ${pull_output}"
        else
            log_warn "${context} Failed to pull latest changes."
        fi
        return 1
    fi

    return 0
}

# ─── Claim protocol ───────────────────────────────────────────────

claim_session() {
    local session_id="$1"
    local session_file
    session_file=$(ensure_session_dir "$session_id")

    if [[ ! -f "$session_file" ]]; then
        log_bad "Session file not found: ${session_id}"
        return 1
    fi

    local status
    status=$(jq -r '.status' "$session_file")
    if [[ "$status" != "queued" ]]; then
        log_bad "Session ${session_id} is not queued (status: ${status})"
        return 1
    fi

    local now hostname_val
    now=$(date -u +%FT%TZ)
    hostname_val=$(hostname)

    jq --arg host "$hostname_val" \
       --arg now "$now" \
       '.status = "active"
        | .claimed_by = $host
        | .claimed_at = $now
        | .updated_at = $now' \
       "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    git -C "$REPO_ROOT" add "${SESSION_DIR}/${session_id}/"
    git -C "$REPO_ROOT" commit -m "agent: claim session ${session_id}" --quiet

    log_info "Pushing claim for ${session_id}..."
    if ! git -C "$REPO_ROOT" push --quiet 2>/dev/null; then
        log_bad "Push failed — session likely claimed by another agent."
        git -C "$REPO_ROOT" reset --hard HEAD~1 --quiet
        return 1
    fi

    log_good "Claimed session ${session_id}"
    return 0
}

# ─── Agent invocation ─────────────────────────────────────────────

invoke_agent() {
    local session_id="$1"
    local cli="${2:-}"
    local model="${3:-}"
    local session_file
    session_file=$(ensure_session_dir "$session_id")

    # Resolve CLI and model
    local session_model
    session_model=$(jq -r '.model // empty' "$session_file")

    if [[ -z "$cli" ]]; then
        cli=$(config_resolve_cli "$session_model")
    fi
    if [[ -z "$model" ]]; then
        model="${session_model:-$(config_default_model "$cli")}"
    fi

    # Extract prompt
    local prompt
    prompt=$(jq -r '.prompt // ""' "$session_file")

    if [[ -z "$prompt" ]]; then
        log_bad "No prompt found in session ${session_id}"
        return 1
    fi

    # Strip YAML frontmatter
    if [[ "$prompt" == ---* ]]; then
        local stripped
        stripped=$(printf '%s\n' "$prompt" | awk '/^---$/ { count++; next } count >= 2 { print }')
        if [[ -n "$stripped" ]]; then
            prompt="$stripped"
        fi
    fi

    # Non-interactive context
    if [[ "$AGENT_NON_INTERACTIVE" == "true" ]]; then
        prompt="${prompt}

---
IMPORTANT: You are running in a non-interactive, headless environment. There is no human to respond to follow-up questions. You must:
1. Complete the task fully in a single pass — do not ask clarifying questions
2. Create a feature branch, commit your work, push, and create a PR with 'gh pr create'
3. If the task is ambiguous, make reasonable assumptions and proceed
4. Do not stop to ask 'Would you like me to...?' — just do it"
    fi

    log_info "Launching ${cli} (${model})..."
    echo ""

    AGENT_CONV_ID=""
    local agent_exit=0
    local stderr_file="/tmp/patchboard-stderr-${session_id}.txt"
    local stdout_file="/tmp/patchboard-stdout-${session_id}.txt"

    local timeout_cmd=""
    if [[ "${AGENT_TIMEOUT:-0}" -gt 0 ]]; then
        log_dim "Timeout: ${AGENT_TIMEOUT}s"
        timeout_cmd="timeout --foreground --signal TERM --kill-after 30 ${AGENT_TIMEOUT}"
    fi

    if [[ "$cli" == "claude" ]]; then
        if [[ "$AGENT_NON_INTERACTIVE" == "true" ]]; then
            set +eo pipefail
            $timeout_cmd claude --model "$model" -p "$prompt" \
                --output-format stream-json --verbose --include-partial-messages \
                --dangerously-skip-permissions \
                2> >(tee "$stderr_file" >&2) | tee "$stdout_file" | \
                jq -rj 'select(.type == "stream_event" and .event.delta?.type? == "text_delta") | .event.delta.text' 2>/dev/null
            agent_exit=${PIPESTATUS[0]}
            wait 2>/dev/null
            set -eo pipefail

            # Capture conversation ID
            if [[ -f "$stdout_file" ]]; then
                local extracted_id=""
                extracted_id=$(jq -r 'select(.type == "system") | .session_id // empty' "$stdout_file" 2>/dev/null | head -1) || true
                if [[ -n "$extracted_id" ]]; then
                    AGENT_CONV_ID="$extracted_id"
                    log_dim "Captured session ID: ${AGENT_CONV_ID}"
                fi
            fi
        else
            $timeout_cmd claude --model "$model" \
                --dangerously-skip-permissions \
                "$prompt"
            agent_exit=$?
        fi
    else
        # Copilot
        if [[ "$AGENT_NON_INTERACTIVE" == "true" ]]; then
            $timeout_cmd copilot --model "$model" \
                -p "$prompt" \
                --allow-all-tools \
                2> >(tee "$stderr_file" >&2) | tee "$stdout_file"
            agent_exit=${PIPESTATUS[0]}
        else
            $timeout_cmd copilot --model "$model" \
                --allow-all-tools \
                "$prompt"
            agent_exit=$?
        fi
    fi

    return $agent_exit
}

# ─── Session status update ────────────────────────────────────────

update_session_status() {
    local session_id="$1"
    local exit_code="$2"
    local stderr_content="${3:-}"
    local pr_url="${4:-}"
    local session_file
    session_file=$(ensure_session_dir "$session_id")
    local now
    now=$(date -u +%FT%TZ)

    if [[ $exit_code -eq 0 ]]; then
        log_good "Marking session as completed."
        jq --arg now "$now" \
           --arg conv_id "$AGENT_CONV_ID" \
           --arg pr_url "$pr_url" \
           '.status = "completed"
            | .completed_at = $now
            | .updated_at = $now
            | if $conv_id != "" then .config.conversation_id = $conv_id else . end
            | if $pr_url != "" then .config.pr_url = $pr_url else . end' \
           "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
    else
        log_bad "Marking session as failed (exit code ${exit_code})."
        jq --arg now "$now" \
           --arg err "$stderr_content" \
           --arg conv_id "$AGENT_CONV_ID" \
           --arg pr_url "$pr_url" \
           '.status = "failed"
            | .completed_at = $now
            | .updated_at = $now
            | .error_message = $err
            | if $conv_id != "" then .config.conversation_id = $conv_id else . end
            | if $pr_url != "" then .config.pr_url = $pr_url else . end' \
           "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
    fi

    git -C "$REPO_ROOT" add "${SESSION_DIR}/${session_id}/"
    git -C "$REPO_ROOT" commit -m "agent: session ${session_id} $(if [[ $exit_code -eq 0 ]]; then echo completed; else echo failed; fi)" --quiet 2>/dev/null || true

    local push_ok=false
    for attempt in 1 2 3; do
        if git -C "$REPO_ROOT" push --quiet 2>/dev/null; then
            push_ok=true
            break
        fi
        log_warn "Push failed (attempt ${attempt}/3), pulling and retrying..."
        git -C "$REPO_ROOT" pull --rebase --quiet 2>/dev/null || true
    done

    if [[ "$push_ok" == "false" ]]; then
        log_bad "Failed to push session status after 3 attempts."
    fi
}

# ─── Transcript management ────────────────────────────────────────

cleanup_session_run_artifacts() {
    local session_id="$1"
    local session_subdir
    session_subdir=$(runtime_session_subdir "$session_id")
    local stdout_tmp="/tmp/patchboard-stdout-${session_id}.txt"
    local stderr_tmp="/tmp/patchboard-stderr-${session_id}.txt"
    local diag_file="${SESSION_DIR}/${session_id}-diagnostic.md"
    local stale_found=false
    local artifact

    # Short-term: clear fixed per-run artifact paths before a rerun so one
    # attempt cannot leak files into the next. Longer-term, these should move
    # to per-attempt artifact directories instead of being overwritten in place.
    for artifact in \
        "${session_subdir}/transcript.jsonl" \
        "${session_subdir}/transcript.jsonl.gz" \
        "${session_subdir}/summary.txt" \
        "$stdout_tmp" \
        "$stderr_tmp" \
        "$diag_file"; do
        if [[ -e "$artifact" ]]; then
            stale_found=true
            if ! rm -f "$artifact"; then
                log_bad "Failed to remove stale run artifact: ${artifact}"
                return 1
            fi
        fi
    done

    if [[ "$stale_found" == "true" ]]; then
        log_dim "Cleared stale run artifacts for ${session_id}"
    fi
}

persist_transcript() {
    local session_id="$1"
    local stdout_tmp="/tmp/patchboard-stdout-${session_id}.txt"
    local session_subdir
    session_subdir=$(runtime_session_subdir "$session_id")

    if [[ ! -s "$stdout_tmp" ]]; then return; fi

    mv "$stdout_tmp" "${session_subdir}/transcript.jsonl"

    # Summary
    {
        jq -rj 'select(.type == "stream_event" and .event.delta?.type? == "text_delta") | .event.delta.text // empty' "${session_subdir}/transcript.jsonl" 2>/dev/null || true
        echo ""
        echo "=== Tool Usage ==="
        jq -r 'select(.type == "stream_event" and .event.type? == "content_block_start" and .event.content_block?.type? == "tool_use") | "- " + (.event.content_block.name // "unknown")' "${session_subdir}/transcript.jsonl" 2>/dev/null || true
        echo ""
        echo "=== Final Result ==="
        jq -rj 'select(.type == "result") | .result // empty' "${session_subdir}/transcript.jsonl" 2>/dev/null || true
    } > "${session_subdir}/summary.txt"

    # Issue encountered: on session re-runs, transcript.jsonl.gz may already
    # exist. Plain gzip prompts before overwrite; with stderr redirected that
    # prompt is invisible, so auto mode appears to hang silently until stopped.
    gzip -f "${session_subdir}/transcript.jsonl" 2>/dev/null || true
}

# ─── Recovery ─────────────────────────────────────────────────────

attempt_recovery() {
    local reason="$1"
    local branch="$2"
    local cli
    cli=$(config_get "cli")
    cli="${cli:-claude}"

    local recovery_prompt=""
    case "$reason" in
        incomplete_delivery)
            recovery_prompt="You completed your work but left uncommitted changes on main without creating a branch or PR. Please deliver your work now: create a feature branch, commit all your changes, push the branch, and create a PR with 'gh pr create'. Do not leave changes on main."
            ;;
        no_pr)
            recovery_prompt="You were working on branch '${branch}' but did not create a pull request. Please create a PR for this branch now using 'gh pr create' with an appropriate title and description based on your changes."
            ;;
        *)
            recovery_prompt="Please ensure your work is complete: branch is pushed, PR is created, and all changes are committed."
            ;;
    esac

    log_warn "Attempting recovery (reason: ${reason})..."

    local recovery_exit=0
    if [[ "$cli" == "claude" && -n "$AGENT_CONV_ID" ]]; then
        log_info "Resuming Claude session ${AGENT_CONV_ID}..."
        claude --resume "$AGENT_CONV_ID" \
            -p "$recovery_prompt" \
            --permission-mode bypassPermissions \
            2>/dev/null || recovery_exit=$?
    elif [[ "$cli" == "copilot" ]]; then
        log_info "Resuming Copilot session..."
        copilot --continue \
            -p "$recovery_prompt" \
            --allow-all-tools \
            2>/dev/null || recovery_exit=$?
    else
        log_warn "No conversation ID — skipping recovery."
        return 1
    fi

    if [[ $recovery_exit -ne 0 ]]; then
        log_bad "Recovery agent exited with code ${recovery_exit}."
    else
        log_good "Recovery completed."
    fi

    return 0
}

# ─── Post-run verification ────────────────────────────────────────

post_run_verify() {
    local session_id="$1"
    local agent_exit="$2"
    local stderr_content="${3:-}"
    local stdout_content="${4:-}"
    local session_file
    session_file=$(ensure_session_dir "$session_id")

    local current_branch default_branch
    current_branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
    current_branch="${current_branch:-unknown}"
    if ! default_branch=$(config_resolve_branch); then
        return 1
    fi

    log_dim "Current branch: ${current_branch}"

    if [[ "$current_branch" == "$default_branch" ]]; then
        local head_msg dirty_files
        head_msg=$(git -C "$REPO_ROOT" log -1 --format="%s" 2>/dev/null || echo "")
        dirty_files=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null \
            | grep -vc "cloud-agents/${session_id}" || true)

        if [[ "$head_msg" == "agent: claim session ${session_id}" && "$dirty_files" -gt 0 && $agent_exit -eq 0 ]]; then
            log_warn "Agent left ${dirty_files} uncommitted file(s) on ${default_branch}."
            if attempt_recovery "incomplete_delivery" "$current_branch"; then
                local post_branch
                post_branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
                post_branch="${post_branch:-$default_branch}"
                if [[ "$post_branch" != "$default_branch" ]]; then
                    log_good "Recovery created branch '${post_branch}'"
                    current_branch="$post_branch"
                else
                    return 1
                fi
            else
                return 1
            fi
        elif [[ "$head_msg" == "agent: claim session ${session_id}" && "$dirty_files" -eq 0 && $agent_exit -eq 0 ]]; then
            log_bad "Agent exited 0 but produced no work."
            create_diagnostic_pr "$session_id" "no work produced" "1" "$stderr_content" "$stdout_content"
            return 0
        else
            return 1
        fi
    fi

    # Feature branch — verify push and PR
    local remote_ref
    remote_ref=$(git -C "$REPO_ROOT" ls-remote --heads origin "$current_branch" 2>/dev/null || echo "")

    if [[ -z "$remote_ref" ]]; then
        log_info "Pushing branch '${current_branch}'..."
        git -C "$REPO_ROOT" push -u origin "$current_branch" --quiet 2>/dev/null || true
    else
        local unpushed
        unpushed=$(git -C "$REPO_ROOT" log "origin/${current_branch}..HEAD" --oneline 2>/dev/null | wc -l)
        if [[ "$unpushed" -gt 0 ]]; then
            log_info "Pushing ${unpushed} commit(s)..."
            git -C "$REPO_ROOT" push --quiet 2>/dev/null || true
        fi
    fi

    # Check PR
    local pr_url=""
    if command -v gh &>/dev/null; then
        pr_url=$(gh pr list --head "$current_branch" --json url --jq '.[0].url' 2>/dev/null || echo "")
    fi

    if [[ -z "$pr_url" ]]; then
        log_warn "No PR found for '${current_branch}'."
        attempt_recovery "no_pr" "$current_branch" || true
        if command -v gh &>/dev/null; then
            pr_url=$(gh pr list --head "$current_branch" --json url --jq '.[0].url' 2>/dev/null || echo "")
        fi

        if [[ -z "$pr_url" ]] && command -v gh &>/dev/null; then
            log_warn "Creating fallback PR..."
            local task_label
            task_label=$(jq -r 'if .task_ids then (.task_ids | join(", ")) else .task_id // "" end' "$session_file")
            pr_url=$(gh pr create \
                --head "$current_branch" \
                --title "Agent session ${session_id}: ${task_label}" \
                --body "Automated PR from agent session \`${session_id}\`.

**Tasks:** ${task_label}
**Agent exit code:** ${agent_exit}

> This PR was created by the post-run verification system." \
                2>/dev/null || echo "")
            [[ -n "$pr_url" ]] && log_good "Fallback PR: ${pr_url}"
        fi
    else
        log_good "PR exists: ${pr_url}"
    fi

    # Update status on the default branch so management-plane state does not
    # dirty the task branch and block checkout back to the orchestrator branch.
    if [[ "$current_branch" != "$default_branch" ]]; then
        if ! ensure_on_default_branch; then
            return 1
        fi
    fi

    local current_status
    current_status=$(jq -r '.status // "unknown"' "$session_file" 2>/dev/null || echo "unknown")

    if [[ "$current_status" != "completed" && "$current_status" != "failed" && "$current_status" != "stopped" ]]; then
        update_session_status "$session_id" "$agent_exit" "$stderr_content" "$pr_url"
    elif [[ -n "$pr_url" ]]; then
        local existing_pr
        existing_pr=$(jq -r '.config.pr_url // ""' "$session_file")
        if [[ -z "$existing_pr" ]]; then
            if [[ -n "$AGENT_CONV_ID" ]]; then
                jq --arg url "$pr_url" --arg conv_id "$AGENT_CONV_ID" \
                   '.config.pr_url = $url | .config.conversation_id = $conv_id' \
                   "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
            else
                jq --arg url "$pr_url" '.config.pr_url = $url' \
                   "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
            fi
            git -C "$REPO_ROOT" add "$session_file"
            git -C "$REPO_ROOT" commit -m "agent: session ${session_id} link PR" --quiet 2>/dev/null || true
            git -C "$REPO_ROOT" push --quiet 2>/dev/null || true
        elif [[ -n "$AGENT_CONV_ID" ]]; then
            jq --arg conv_id "$AGENT_CONV_ID" '.config.conversation_id = $conv_id' \
               "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
            git -C "$REPO_ROOT" add "$session_file"
            git -C "$REPO_ROOT" commit -m "agent: session ${session_id} link conversation" --quiet 2>/dev/null || true
            git -C "$REPO_ROOT" push --quiet 2>/dev/null || true
        fi
    fi

    log_good "Verification complete."
    return 0
}

# ─── Diagnostic PR ────────────────────────────────────────────────

create_diagnostic_pr() {
    local session_id="$1"
    local failure_reason="$2"
    local exit_code="$3"
    local stderr_content="${4:-}"
    local stdout_content="${5:-}"
    local session_file
    session_file=$(ensure_session_dir "$session_id")

    log_warn "Creating diagnostic PR for ${session_id}..."

    local error_detail="${failure_reason}"
    if [[ -n "$stdout_content" ]]; then
        error_detail="${error_detail} Agent output (last 2048 chars): ${stdout_content: -2048}"
    fi

    local default_branch
    if ! default_branch=$(config_resolve_branch); then
        return 1
    fi

    if ! ensure_on_default_branch; then
        return 1
    fi
    update_session_status "$session_id" "$exit_code" "$error_detail"
    pull_latest_with_warning "[diagnostic]"

    local diag_branch="agent/diagnostic/${session_id}"
    if ! git -C "$REPO_ROOT" checkout -b "$diag_branch" --quiet 2>/dev/null; then
        log_bad "Failed to create diagnostic branch."
        return 1
    fi

    local prompt task_ids model claimed_by claimed_at started_at now
    prompt=$(jq -r '.prompt // "N/A"' "$session_file")
    task_ids=$(jq -r 'if .task_ids and (.task_ids | length > 0) then (.task_ids | join(", ")) else .task_id // "N/A" end' "$session_file")
    model=$(jq -r '.model // "N/A"' "$session_file")
    claimed_by=$(jq -r '.claimed_by // "N/A"' "$session_file")
    claimed_at=$(jq -r '.claimed_at // "N/A"' "$session_file")
    started_at=$(jq -r '.started_at // "N/A"' "$session_file")
    now=$(date -u +%FT%TZ)

    local diag_file="${SESSION_DIR}/${session_id}-diagnostic.md"
    cat > "$diag_file" <<EOF
# Agent Diagnostic Report: ${session_id}

## Session Metadata

| Field | Value |
|-------|-------|
| Session ID | \`${session_id}\` |
| Task IDs | ${task_ids} |
| Model | ${model} |
| Claimed By | ${claimed_by} |
| Claimed At | ${claimed_at} |
| Started At | ${started_at} |
| Failed At | ${now} |
| Exit Code | ${exit_code} |

## Failure Reason

${failure_reason}

## Prompt

\`\`\`
${prompt}
\`\`\`

## Agent stdout (last 4096 chars)

\`\`\`
${stdout_content:-<no output captured>}
\`\`\`

## Agent stderr (last 4096 chars)

\`\`\`
${stderr_content:-<no stderr captured>}
\`\`\`
EOF

    git -C "$REPO_ROOT" add "$diag_file" "$session_file"
    if ! git -C "$REPO_ROOT" commit -m "agent: diagnostic report for ${session_id} (${failure_reason})" --quiet 2>/dev/null; then
        log_bad "Failed to commit diagnostic file."
        git -C "$REPO_ROOT" checkout "$default_branch" --quiet 2>/dev/null || true
        return 1
    fi

    if ! git -C "$REPO_ROOT" push -u origin "$diag_branch" --quiet 2>/dev/null; then
        log_bad "Failed to push diagnostic branch."
        git -C "$REPO_ROOT" checkout "$default_branch" --quiet 2>/dev/null || true
        return 1
    fi

    local pr_url=""
    if command -v gh &>/dev/null; then
        pr_url=$(gh pr create \
            --head "$diag_branch" \
            --title "Agent diagnostic: ${session_id} (${failure_reason})" \
            --body "Diagnostic report for failed agent session \`${session_id}\`.

**Failure reason:** ${failure_reason}
**Exit code:** ${exit_code}
**Task IDs:** ${task_ids}
**Model:** ${model}

> This PR was automatically created by the agent bot diagnostic system." \
            2>/dev/null || echo "")
    fi

    if [[ -n "$pr_url" ]]; then
        log_good "Diagnostic PR: ${pr_url}"
    fi

    git -C "$REPO_ROOT" checkout "$default_branch" --quiet 2>/dev/null || true
    if [[ -n "$pr_url" ]]; then
        jq --arg url "$pr_url" '.config.diagnostic_pr_url = $url' \
           "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
        git -C "$REPO_ROOT" add "$session_file"
        git -C "$REPO_ROOT" commit -m "agent: session ${session_id} link diagnostic PR" --quiet 2>/dev/null || true
        git -C "$REPO_ROOT" push --quiet 2>/dev/null || true
    fi
    return 0
}

# ─── Full session lifecycle ────────────────────────────────────────

# Run a complete session: claim → invoke → verify → update
# Usage: run_session "se-XXXXX" [cli] [model]
run_session() {
    local session_id="$1"
    local cli="${2:-}"
    local model="${3:-}"
    local session_file
    session_file=$(ensure_session_dir "$session_id")

    local status
    status=$(jq -r '.status' "$session_file" 2>/dev/null || echo "unknown")

    # Claim if queued
    if [[ "$status" == "queued" ]]; then
        if ! claim_session "$session_id"; then
            log_bad "Failed to claim session ${session_id}."
            return 1
        fi
    elif [[ "$status" == "active" || "$status" == "failed" || "$status" == "completed" ]]; then
        log_warn "Session ${session_id} has status '${status}'."
        log_warn "Re-running prompt without claiming or updating status."
        if ! confirm "Continue?"; then
            log_dim "Cancelled."
            return 1
        fi
    else
        log_bad "Session ${session_id} has unexpected status '${status}'."
        return 1
    fi

    if ! cleanup_session_run_artifacts "$session_id"; then
        return 1
    fi

    # Invoke
    local rc=0
    invoke_agent "$session_id" "$cli" "$model" || rc=$?

    # Capture stderr/stdout
    local stderr_content="" stdout_content=""
    local stderr_tmp="/tmp/patchboard-stderr-${session_id}.txt"
    local stdout_tmp="/tmp/patchboard-stdout-${session_id}.txt"

    if [[ -s "$stderr_tmp" ]]; then
        stderr_content=$(head -c 4096 "$stderr_tmp")
        rm -f "$stderr_tmp"
    fi
    if [[ -s "$stdout_tmp" ]]; then
        stdout_content=$(jq -rj 'select(.type == "result") | .result // empty' "$stdout_tmp" 2>/dev/null) || true
        if [[ -z "$stdout_content" ]]; then
            stdout_content=$(jq -rj 'select(.type == "stream_event" and .event.delta?.type? == "text_delta") | .event.delta.text' "$stdout_tmp" 2>/dev/null) || true
        fi
        if [[ -z "$stdout_content" ]]; then
            stdout_content=$(tail -c 4096 "$stdout_tmp")
        fi
        persist_transcript "$session_id"
    fi

    echo ""

    # Post-run (only for claimed sessions)
    if [[ "$status" == "queued" ]]; then
        local session_handled=false
        if post_run_verify "$session_id" "$rc" "$stderr_content" "$stdout_content"; then
            session_handled=true
        fi

        if [[ "$session_handled" == "false" ]]; then
            if [[ $rc -ne 0 ]]; then
                local failure_reason="non-zero exit"
                [[ $rc -eq 124 ]] && failure_reason="timeout (exceeded ${AGENT_TIMEOUT}s)"
                create_diagnostic_pr "$session_id" "$failure_reason" "$rc" "$stderr_content" "$stdout_content"
            else
                update_session_status "$session_id" "$rc" "$stderr_content"
            fi
        fi

        if ! ensure_on_default_branch; then
            return 1
        fi
    fi

    log_info "Session ${session_id} done (exit code: ${rc})."
    return $rc
}
