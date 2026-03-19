#!/usr/bin/env bash
#
# patchboard - Unified CLI for patchboard agent orchestration
#
# Usage: patchboard <command> [args]
#
# Commands:
#   version      Display tooling version
#   healthcheck  Run system healthchecks
#   list         List sessions, tasks, or pull requests
#   start [id]   Start a session (accepts session/task/PR id, or interactive)
#   auto         Auto-poll and process queued sessions
#   cli          Configure default AI CLI
#   branch       Configure main branch
#   status       Show current settings and session state
#   upgrade      Pull latest tooling from the public repo
#
# Install: .patchboard/tooling/install.sh

set -euo pipefail

# ─── Paths ──────────────────────────────────────────────────────────
# Resolve symlinks to find the real script directory
_resolve_script() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        local dir
        dir="$(cd "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="${dir}/${source}"
    done
    cd "$(dirname "$source")" && pwd
}
SCRIPT_DIR="$(_resolve_script)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$SCRIPT_DIR")")"
SESSION_DIR="${REPO_ROOT}/.patchboard/state/cloud-agents"
PATCHBOARD_VERSION="$(cat "${REPO_ROOT}/.patchboard/VERSION" 2>/dev/null || echo "unknown")"
PATCHBOARD_BRANCH_OVERRIDE=""

# ─── Source libraries ──────────────────────────────────────────────
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/sessions.sh"
source "${SCRIPT_DIR}/lib/tasks.sh"
source "${SCRIPT_DIR}/lib/prs.sh"
source "${SCRIPT_DIR}/lib/prompts.sh"
source "${SCRIPT_DIR}/lib/health.sh"
source "${SCRIPT_DIR}/lib/agent.sh"

# ─── Prerequisites ─────────────────────────────────────────────────
_check_jq() {
    if ! command -v jq &>/dev/null; then
        echo -e "${BAD}Error: jq is required but not installed.${NC}" >&2
        exit 1
    fi
}

# ─── Commands ──────────────────────────────────────────────────────

cmd_version() {
    print_box_header "Patchboard  v${PATCHBOARD_VERSION}"
    print_kv "Version" "$PATCHBOARD_VERSION"
    print_kv "Tooling dir" "$SCRIPT_DIR"
    print_kv "Repo root" "$REPO_ROOT"
    print_kv "Session dir" "$SESSION_DIR"

    # Show configured settings
    local cli branch
    cli=$(config_get "cli")
    branch=$(config_get "branch")
    echo ""
    print_kv "CLI" "${cli:-claude}"
    print_kv "Branch" "${branch:-main}"
    echo ""
}

cmd_healthcheck() {
    print_box_header "Healthcheck"
    _check_jq
    run_healthcheck
}

cmd_list() {
    _check_jq
    local subcommand="${1:-sessions}"

    # Backward compat: if first arg is a number or a status, treat as session listing
    if [[ "$subcommand" =~ ^[0-9]+$ ]] || [[ "$subcommand" =~ ^(queued|active|failed|completed|stopped)$ ]]; then
        _list_sessions "$subcommand" "${2:-}"
        return
    fi

    shift || true

    case "$subcommand" in
        sessions|s)
            _list_sessions "$@"
            ;;
        tasks|t)
            _list_tasks "$@"
            ;;
        prs|pr|pulls)
            _list_prs "$@"
            ;;
        *)
            log_bad "Unknown list type: ${subcommand}"
            echo -e "  Usage: patchboard list ${CYAN}[sessions|tasks|prs]${NC} [options]"
            return 1
            ;;
    esac
}

_list_sessions() {
    local limit="${1:-20}"
    local status_filter="${2:-}"

    print_section "Sessions"

    if [[ -n "$status_filter" ]]; then
        log_dim "Filter: status=${status_filter}"
        local sessions
        sessions=$(discover_sessions "$status_filter")
        sessions=$(echo "$sessions" | jq 'sort_by(.updated_at // .started_at) | reverse')
        sessions=$(echo "$sessions" | jq --argjson n "$limit" '.[:$n]')
        print_session_table "$sessions"
    else
        log_dim "Showing ${limit} most recently modified"
        local sessions
        sessions=$(discover_recent "$limit")
        print_session_table "$sessions"
    fi
}

_list_tasks() {
    local limit="${1:-30}"
    local status_filter="${2:-}"

    print_section "Tasks"

    local tasks
    tasks=$(discover_tasks "$status_filter")

    if [[ -n "$status_filter" ]]; then
        log_dim "Filter: status=${status_filter}"
    fi

    tasks=$(echo "$tasks" | jq --argjson n "$limit" '.[:$n]')
    print_task_table "$tasks"
}

_list_prs() {
    local limit="${1:-30}"
    local state="${2:-open}"

    print_section "Pull Requests"
    log_dim "State: ${state}"

    local prs
    prs=$(discover_prs "$state" "$limit")
    print_pr_table "$prs"
}

cmd_start() {
    _check_jq
    local id="${1:-}"

    # ── Detect ID type and route ─────────────────────────────────
    if [[ -n "$id" ]]; then
        case "$id" in
            se-*)
                _start_session "$id"
                return $?
                ;;
            [TE]-[0-9]*)
                _start_from_task "$id"
                return $?
                ;;
            \#[0-9]*|[0-9]*)
                local pr_num="${id#\#}"
                _start_from_pr "$pr_num"
                return $?
                ;;
            *)
                log_bad "Unrecognised ID format: ${id}"
                echo -e "  Expected: ${CYAN}se-*${NC} (session), ${CYAN}T-*${NC} (task), or ${CYAN}#N${NC} / ${CYAN}N${NC} (PR)"
                return 1
                ;;
        esac
    fi

    # ── No ID: interactive flow ──────────────────────────────────
    print_box_header "Start"

    echo -e "  ${BRAND}What do you want to work on?${NC}"
    echo ""
    echo -e "    ${CYAN}s)${NC} Existing session"
    echo -e "    ${CYAN}t)${NC} Task"
    echo -e "    ${CYAN}p)${NC} Pull Request"
    echo ""
    read -p "  Select [s/t/p]: " source_type

    case "$source_type" in
        s|S|session)
            print_section "Select Session"
            if ! select_session; then
                return 1
            fi
            _start_session "$SELECTED_SESSION_ID"
            ;;
        t|T|task)
            print_section "Select Task"
            if ! select_task; then
                return 1
            fi
            _start_from_task "$SELECTED_TASK_ID"
            ;;
        p|P|pr)
            print_section "Select Pull Request"
            if ! select_pr; then
                return 1
            fi
            _start_from_pr "$SELECTED_PR_NUMBER"
            ;;
        *)
            log_bad "Invalid selection."
            return 1
            ;;
    esac
}

# ─── Start helpers ───────────────────────────────────────────────

# Start an existing session by ID
_start_session() {
    local session_id="$1"

    print_box_header "Starting  ${session_id}"

    local sf
    sf=$(ensure_session_dir "$session_id")
    local status tasks cli model
    status=$(jq -r '.status // "?"' "$sf")
    tasks=$(jq -r 'if .task_ids then (.task_ids | join(", ")) else .task_id // "" end' "$sf")
    local session_model
    session_model=$(jq -r '.model // empty' "$sf")

    cli=$(config_resolve_cli "$session_model")
    model="${session_model:-$(config_default_model "$cli")}"

    print_kv "Session" "$session_id"
    print_kv "Status" "$status"
    print_kv "Tasks" "$tasks"
    print_kv "CLI" "$cli"
    print_kv "Model" "$model"
    print_kv "Timeout" "${AGENT_TIMEOUT}s"
    echo ""

    _show_permissions "$cli"

    if ! confirm "Proceed?"; then
        log_dim "Cancelled."
        return 0
    fi

    echo ""
    ensure_on_main
    git -C "$REPO_ROOT" pull --rebase --quiet 2>/dev/null || true

    run_session "$session_id" "$cli" "$model"
    local rc=$?
    config_set "selected_session" ""
    return $rc
}

# Create a new session from a task ID and start it
_start_from_task() {
    local task_id="$1"
    local task_ids=("$task_id")
    local template_vars=("TASK_ID=$task_id")

    # Look up task title if discoverable
    local title=""
    local tasks_json
    tasks_json=$(discover_tasks)
    title=$(echo "$tasks_json" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .title // ""')
    [[ -n "$title" ]] && template_vars+=("TITLE=$title")

    log_good "Task: ${task_id}${title:+ — ${title}}"

    _enqueue_and_run task_ids template_vars "" ""
}

# Create a new session from a PR number and start it
_start_from_pr() {
    local pr_num="$1"
    local template_vars=("PR_NUMBER=$pr_num")

    # Look up PR details
    local pr_branch="" pr_title=""
    if command -v gh &>/dev/null; then
        pr_branch=$(gh pr view "$pr_num" --json headRefName --jq '.headRefName' 2>/dev/null || echo "")
        pr_title=$(gh pr view "$pr_num" --json title --jq '.title' 2>/dev/null || echo "")
    fi
    [[ -n "$pr_branch" ]] && template_vars+=("BRANCH=$pr_branch")
    [[ -n "$pr_title" ]] && template_vars+=("TITLE=$pr_title")

    log_good "PR: #${pr_num}${pr_title:+ — ${pr_title}}"

    # Extract task IDs from PR title/branch
    local task_ids=()
    local pr_task_ids
    pr_task_ids=$(echo "$pr_title $pr_branch" | grep -oE '[TE]-[0-9]+' | sort -u)
    while IFS= read -r tid; do
        [[ -n "$tid" ]] && task_ids+=("$tid")
    done <<< "$pr_task_ids"

    _enqueue_and_run task_ids template_vars "$pr_num" "$pr_branch"
}

# Shared: pick workspace/prompt/model, create session, and run it.
# Usage: _enqueue_and_run <task_ids_nameref> <template_vars_nameref> [pr_number] [pr_branch]
_enqueue_and_run() {
    local -n _task_ids=$1
    local -n _template_vars=$2
    local pr_number="${3:-}"
    local pr_branch="${4:-}"

    # ── Select agent workspace ───────────────────────────────────
    print_section "Agent Workspace"
    if ! select_workspace; then
        return 1
    fi
    local workspace="$SELECTED_WORKSPACE"

    # ── Select prompt ────────────────────────────────────────────
    print_section "Prompt"
    if ! select_prompt "$workspace"; then
        return 1
    fi

    local prompt
    prompt=$(render_prompt "$SELECTED_PROMPT" "${_template_vars[@]}")

    # Prepend agent role instruction if index.md exists
    local agent_index="${AGENTS_DIR}/${workspace}/index.md"
    if [[ -f "$agent_index" ]]; then
        prompt="Read .patchboard/agents/${workspace}/index.md and confirm that you have read this and understand your role.

${prompt}"
    fi

    # ── Select model ─────────────────────────────────────────────
    echo ""
    prompt_choice "Model" "sonnet" "opus" "haiku"
    local model="$REPLY"

    # ── Create session file ──────────────────────────────────────
    local session_id uuid now
    uuid=$(generate_uuid)
    session_id="se-${uuid:0:12}"
    now=$(date -u +%FT%TZ)

    local session_dir="${SESSION_DIR}/${session_id}"
    mkdir -p "$session_dir"

    local task_ids_json
    if [[ ${#_task_ids[@]} -gt 0 ]]; then
        task_ids_json=$(printf '%s\n' "${_task_ids[@]}" | jq -R . | jq -s .)
    else
        task_ids_json="[]"
    fi

    local session_json
    session_json=$(jq -n \
        --arg sid "$session_id" \
        --arg status "queued" \
        --arg provider "self_hosted" \
        --argjson task_ids "$task_ids_json" \
        --arg workspace "$workspace" \
        --arg model "$model" \
        --arg prompt "$prompt" \
        --arg now "$now" \
        '{
            session_id: $sid,
            status: $status,
            provider: $provider,
            task_ids: $task_ids,
            workspace_id: $workspace,
            model: $model,
            prompt: $prompt,
            created_at: $now,
            updated_at: $now,
            config: {}
        }')

    echo "$session_json" > "${session_dir}/session.json"

    # ── Summary and confirm ──────────────────────────────────────
    echo ""
    print_section "Session Summary"
    print_kv "Session" "$session_id"
    print_kv "Source" "$(if [[ -n "$pr_number" ]]; then echo "PR #${pr_number}"; else echo "${_task_ids[*]}"; fi)"
    print_kv "Workspace" "$workspace"
    print_kv "Model" "$model"
    print_kv "Tasks" "$(IFS=', '; echo "${_task_ids[*]}")"
    echo ""
    echo -e "  ${DIM}Prompt (first 3 lines):${NC}"
    echo "$prompt" | head -3 | while IFS= read -r line; do
        echo -e "    ${DIM}${line}${NC}"
    done
    echo ""

    local cli
    cli=$(config_resolve_cli "$model")
    _show_permissions "$cli"

    if ! confirm "Create session and start?"; then
        rm -rf "$session_dir"
        log_dim "Cancelled."
        return 1
    fi

    # ── Git commit + push ────────────────────────────────────────
    git -C "$REPO_ROOT" add "${session_dir}/"
    git -C "$REPO_ROOT" commit -m "enqueue: session ${session_id} (${workspace})" --quiet

    log_info "Pushing session..."
    if ! git -C "$REPO_ROOT" push --quiet 2>/dev/null; then
        log_warn "Push failed, pulling and retrying..."
        git -C "$REPO_ROOT" pull --rebase --quiet 2>/dev/null || true
        if ! git -C "$REPO_ROOT" push --quiet 2>/dev/null; then
            log_bad "Failed to push session."
            return 1
        fi
    fi

    log_good "Session ${session_id} enqueued."
    echo ""

    # ── Run it ───────────────────────────────────────────────────
    ensure_on_main
    git -C "$REPO_ROOT" pull --rebase --quiet 2>/dev/null || true

    run_session "$session_id" "$cli" "$model"
    local rc=$?
    config_set "selected_session" ""
    return $rc
}

_show_permissions() {
    local cli="$1"
    echo -e "  ${YELLOW}Permissions:${NC}"
    if [[ "$cli" == "claude" ]]; then
        echo -e "    ${BAD}--dangerously-skip-permissions${NC} (full access)"
    else
        echo -e "    ${BAD}--allow-all-tools${NC} (full access)"
    fi
    echo ""
}

cmd_auto() {
    _check_jq
    local poll_interval="${1:-60}"
    local max_sessions="${2:-0}"

    print_box_header "Auto Mode"

    local cli branch
    cli=$(config_get "cli")
    branch=$(config_get "branch")
    branch="${branch:-main}"

    # Cache branch for the duration of auto mode so it survives config deletion
    PATCHBOARD_BRANCH_OVERRIDE="$branch"

    print_kv "CLI" "${cli:-claude}"
    print_kv "Branch" "$branch"
    print_kv "Poll interval" "${poll_interval}s"
    print_kv "Max sessions" "${max_sessions} (0=unlimited)"
    print_kv "Timeout" "${AGENT_TIMEOUT}s"
    echo ""

    # Permissions
    echo -e "  ${YELLOW}Permissions:${NC}"
    echo -e "    ${BAD}Full agent access will be granted${NC}"
    echo ""

    if ! confirm "Start auto-polling?"; then
        PATCHBOARD_BRANCH_OVERRIDE=""
        log_dim "Cancelled."
        return 0
    fi
    echo ""

    local running=true
    local sessions_processed=0

    trap 'echo ""; log_warn "Shutdown requested..."; running=false' INT TERM

    while $running; do
        local ts
        ts=$(date -u '+%Y-%m-%d %H:%M:%SZ')

        ensure_on_main
        log_dim "[${ts}] Pulling latest..."
        git -C "$REPO_ROOT" pull --rebase --quiet 2>/dev/null || true

        # Check for version update
        local current_version
        current_version="$(cat "${REPO_ROOT}/.patchboard/VERSION" 2>/dev/null || echo "unknown")"
        if [[ "$current_version" != "$PATCHBOARD_VERSION" && "$current_version" != "unknown" ]]; then
            log_warn "Version update: v${PATCHBOARD_VERSION} → v${current_version}"
            log_info "Restarting..."
            exec "${BASH_SOURCE[0]}" auto "$poll_interval" "$max_sessions"
        fi

        # Find oldest queued session
        local session_id
        session_id=$(discover_sessions "queued" | jq -r '.[0].session_id // empty')

        if [[ -n "$session_id" ]]; then
            log_info "[${ts}] Found: ${session_id}"

            if run_session "$session_id"; then
                sessions_processed=$(( sessions_processed + 1 ))
            fi

            if [[ "$max_sessions" -gt 0 && "$sessions_processed" -ge "$max_sessions" ]]; then
                log_warn "Reached max sessions (${max_sessions}). Exiting."
                break
            fi
        else
            log_dim "[${ts}] No queued sessions. Sleeping ${poll_interval}s..."
            local i=0
            while [[ $i -lt $poll_interval ]] && $running; do
                sleep 1
                i=$(( i + 1 ))
            done
        fi
    done

    echo ""
    log_info "Auto mode stopped. Processed ${sessions_processed} session(s)."
}

cmd_cli() {
    local choice="${1:-}"

    if [[ -n "$choice" ]]; then
        case "$choice" in
            claude|copilot|auto)
                config_set "cli" "$choice"
                log_good "CLI set to: ${choice}"
                ;;
            *)
                log_bad "Invalid CLI: ${choice}"
                echo -e "  Options: ${CYAN}claude${NC}  ${CYAN}copilot${NC}  ${CYAN}auto${NC}"
                return 1
                ;;
        esac
    else
        print_section "Select CLI"
        echo ""
        local current
        current=$(config_get "cli")
        current="${current:-claude}"

        echo -e "  Current: ${BRAND}${current}${NC}"
        echo ""

        prompt_choice "Choose CLI" "claude" "copilot" "auto (based on session model)"
        local selected="$REPLY"
        # Strip description from auto option
        [[ "$selected" == "auto"* ]] && selected="auto"

        config_set "cli" "$selected"
        log_good "CLI set to: ${selected}"
    fi
    echo ""
}

cmd_branch() {
    local choice="${1:-}"

    if [[ -n "$choice" ]]; then
        config_set "branch" "$choice"
        log_good "Branch set to: ${choice}"
    else
        print_section "Select Main Branch"
        echo ""
        local current
        current=$(config_get "branch")
        current="${current:-main}"

        echo -e "  Current: ${BRAND}${current}${NC}"
        echo ""

        prompt_choice "Choose branch" "main" "trunk" "master" "other"
        local selected="$REPLY"

        if [[ "$selected" == "other" ]]; then
            read -p "  Branch name: " selected
            if [[ -z "$selected" ]]; then
                log_dim "Cancelled."
                return 0
            fi
        fi

        config_set "branch" "$selected"
        log_good "Branch set to: ${selected}"
    fi
    echo ""
}

cmd_status() {
    _check_jq
    print_box_header "Status"

    # Settings
    print_section "Settings"
    local cli branch
    cli=$(config_get "cli")
    branch=$(config_get "branch")
    print_kv "Repo root" "$REPO_ROOT"
    print_kv "CLI" "${cli:-claude}"
    print_kv "Branch" "${branch:-main}"
    print_kv "Version" "$PATCHBOARD_VERSION"

    # Selected session
    local selected
    selected=$(config_get "selected_session")
    if [[ -n "$selected" ]]; then
        echo ""
        print_section "Selected Session"
        local sf
        sf=$(ensure_session_dir "$selected")
        if [[ -f "$sf" ]]; then
            local status tasks
            status=$(jq -r '.status // "?"' "$sf")
            tasks=$(jq -r 'if .task_ids then (.task_ids | join(", ")) else .task_id // "" end' "$sf")
            print_kv "Session" "$selected"
            print_kv "Status" "$(echo -e "$(status_badge "$status")")"
            print_kv "Tasks" "$tasks"
        else
            print_kv "Session" "${selected} ${BAD}(file not found)${NC}"
        fi
    fi

    # Session summary
    echo ""
    print_section "Session Summary"
    local queued active failed completed
    queued=$(discover_sessions "queued" | jq 'length')
    active=$(discover_sessions "active" | jq 'length')
    failed=$(discover_sessions "failed" | jq 'length')
    completed=$(discover_sessions "completed" | jq 'length')

    echo -e "  ${GOOD}${queued}${NC} queued   ${CYAN}${active}${NC} active   ${BAD}${failed}${NC} failed   ${BRAND}${completed}${NC} completed"

    # Check for running agent processes
    echo ""
    print_section "Agent Processes"
    local agent_pids
    agent_pids=$(pgrep -f "patchboard.bash auto|patchboard auto" 2>/dev/null | grep -v "$$" || true)
    if [[ -n "$agent_pids" ]]; then
        echo "$agent_pids" | while IFS= read -r pid; do
            local cmdline
            cmdline=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
            echo -e "  ${CYAN}PID ${pid}${NC}  ${cmdline}"
        done
    else
        log_dim "No agent processes running"
    fi

    echo ""
}

# ─── Upgrade ──────────────────────────────────────────────────────

PATCHBOARD_PUBLIC_REPO="https://github.com/jamesmiles/patchboard-public.git"

cmd_upgrade() {
    local force=false
    [[ "${1:-}" == "force" ]] && force=true

    print_box_header "Upgrade"

    local local_version="$PATCHBOARD_VERSION"
    local tooling_dest="${REPO_ROOT}/.patchboard/tooling"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # Clean up temp dir on exit
    trap 'rm -rf "$tmp_dir"' RETURN

    # Fetch the remote VERSION to compare
    log_info "Checking for updates..."
    if ! git clone --depth 1 "$PATCHBOARD_PUBLIC_REPO" "$tmp_dir/repo" 2>/dev/null; then
        log_bad "Failed to fetch from ${PATCHBOARD_PUBLIC_REPO}"
        return 1
    fi

    local remote_version
    remote_version="$(cat "$tmp_dir/repo/VERSION" 2>/dev/null || echo "unknown")"

    print_kv "Installed" "v${local_version}"
    print_kv "Latest" "v${remote_version}"
    echo ""

    if [[ "$remote_version" == "unknown" ]]; then
        log_bad "Could not determine remote version"
        return 1
    fi

    if [[ "$local_version" == "$remote_version" ]]; then
        log_good "Already up to date."
        echo ""
        return 0
    fi

    # Confirm unless --force
    if [[ "$force" != "true" ]]; then
        log_warn "Upgrading ${YELLOW}v${local_version}${NC} → ${YELLOW}v${remote_version}${NC}"
        echo ""
        echo -e "  ${DIM}This will overwrite .patchboard/ tooling, schemas, and state${NC}"
        echo ""
        if ! confirm "Proceed with upgrade?"; then
            log_dim "Cancelled."
            return 0
        fi
        echo ""
    fi

    local patchboard_dir="${REPO_ROOT}/.patchboard"
    log_info "Installing v${remote_version}..."

    # Copy VERSION into .patchboard/ where runtime looks for it
    cp "$tmp_dir/repo/VERSION" "$patchboard_dir/VERSION"

    # Copy schema directories (additive merge)
    local schema_dir
    for schema_dir in planning schemas state tasks; do
        if [[ -d "$tmp_dir/repo/$schema_dir" ]]; then
            rsync -a "$tmp_dir/repo/$schema_dir/" "$patchboard_dir/$schema_dir/"
        fi
    done

    # Preserve local config before replacing tooling directory
    local config_backup=""
    local config_file="${tooling_dest}/state/config.json"
    if [[ -f "$config_file" ]]; then
        config_backup=$(cat "$config_file")
    fi

    # Replace tooling directory (clean wipe then copy)
    mkdir -p "$tooling_dest"
    rsync -a --delete "$tmp_dir/repo/tooling/" "$tooling_dest/"

    # Restore local config
    if [[ -n "$config_backup" ]]; then
        mkdir -p "${tooling_dest}/state"
        echo "$config_backup" > "$config_file"
    fi
    chmod +x "$tooling_dest/patchboard.bash"
    chmod +x "$tooling_dest/install.sh"

    # Install GitHub Actions workflows if templates exist
    if [[ -d "$tmp_dir/repo/tooling/workflows" ]]; then
        local gh_workflows_dir="${REPO_ROOT}/.github/workflows"
        mkdir -p "$gh_workflows_dir"
        rsync -a "$tmp_dir/repo/tooling/workflows/" "$gh_workflows_dir/"
        log_good "GitHub Actions workflows updated"
    fi

    log_good "Upgraded to v${remote_version}"

    # Re-run install to update symlinks, deps, etc.
    log_info "Running install..."
    echo ""
    bash "$tooling_dest/install.sh"
}

# ─── Help / usage ─────────────────────────────────────────────────

cmd_help() {
    print_box_header "Patchboard  v${PATCHBOARD_VERSION}"

    echo -e "  ${BRAND_BOLD}USAGE${NC}"
    echo -e "    patchboard ${CYAN}<command>${NC} [options]"
    echo ""

    echo -e "  ${BRAND_BOLD}COMMANDS${NC}"
    echo ""

    TABLE_WIDTHS=(22 50)
    TABLE_INDENT="    "
    table_row "version" "Display version and configuration"
    table_row "healthcheck" "Run system healthchecks"
    table_row "list [type]" "List sessions, tasks, or prs"
    table_row "start [id]" "Start session, task, or PR (interactive if no id)"
    table_row "auto [int] [max]" "Auto-poll and process queued sessions"
    table_row "cli [name]" "Configure default CLI (claude/copilot/auto)"
    table_row "branch [name]" "Configure main branch"
    table_row "status" "Show settings and session state"
    table_row "upgrade [force]" "Pull latest tooling from public repo"
    table_row "help" "Show this help"
    TABLE_INDENT="  "
    echo ""

    echo -e "  ${BRAND_BOLD}OPTIONS${NC}"
    echo ""
    TABLE_WIDTHS=(22 55)
    TABLE_INDENT="    "
    table_row "--interactive" "Run agent in interactive mode (default: start)"
    table_row "--non-interactive" "Run agent in non-interactive mode (default: auto)"
    table_row "--timeout SECONDS" "Kill agent after N seconds (default: 86400)"
    TABLE_INDENT="  "
    echo ""

    echo -e "  ${BRAND_BOLD}EXAMPLES${NC}"
    echo ""
    echo -e "    ${DIM}# Interactive: choose session, task, or PR${NC}"
    echo -e "    patchboard start"
    echo ""
    echo -e "    ${DIM}# Start from a specific task or PR${NC}"
    echo -e "    patchboard start T-0311"
    echo -e "    patchboard start 42"
    echo ""
    echo -e "    ${DIM}# Resume an existing session${NC}"
    echo -e "    patchboard start se-abc12345"
    echo ""
    echo -e "    ${DIM}# List tasks, PRs, or sessions${NC}"
    echo -e "    patchboard list tasks"
    echo -e "    patchboard list prs"
    echo ""
    echo -e "    ${DIM}# Auto-poll every 30s, max 5 sessions${NC}"
    echo -e "    patchboard auto 30 5"
    echo ""
    echo -e "    ${DIM}# Upgrade tooling to latest version${NC}"
    echo -e "    patchboard upgrade"
    echo -e "    patchboard upgrade force"
    echo ""
}

# ─── Argument parsing ─────────────────────────────────────────────

# Global flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            AGENT_TIMEOUT="$2"
            shift 2
            ;;
        --non-interactive)
            AGENT_NON_INTERACTIVE=true
            _NI_EXPLICIT=true
            shift
            ;;
        --interactive)
            AGENT_NON_INTERACTIVE=false
            _NI_EXPLICIT=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

command="${1:-help}"
shift || true

# Apply per-command defaults if user didn't explicitly set --interactive/--non-interactive
if [[ "${_NI_EXPLICIT:-}" != "true" ]]; then
    case "$command" in
        start|run)   AGENT_NON_INTERACTIVE=false ;;  # interactive by default
        auto|poll)   AGENT_NON_INTERACTIVE=true ;;   # non-interactive by default
    esac
fi

case "$command" in
    version|v)        cmd_version "$@" ;;
    healthcheck|hc)   cmd_healthcheck "$@" ;;
    list|ls)          cmd_list "$@" ;;
    start|run)        cmd_start "$@" ;;
    auto|poll)        cmd_auto "$@" ;;
    cli)              cmd_cli "$@" ;;
    branch|br)        cmd_branch "$@" ;;
    status|st)        cmd_status "$@" ;;
    upgrade|up)       cmd_upgrade "$@" ;;
    help|--help|-h)   cmd_help "$@" ;;
    *)
        log_bad "Unknown command: ${command}"
        echo ""
        cmd_help
        exit 1
        ;;
esac
