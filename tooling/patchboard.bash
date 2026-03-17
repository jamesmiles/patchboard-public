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
#   select       Interactive session picker
#   start        Start a session (claim + run agent)
#   enqueue      Create a new session from a task or PR
#   spawn        Enqueue + select + start a session
#   auto         Auto-poll and process queued sessions
#   cli          Configure default AI CLI
#   branch       Configure main branch
#   status       Show current settings and session state
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
PATCHBOARD_VERSION="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")"

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

cmd_select() {
    _check_jq
    local session_id="${1:-}"

    if [[ -n "$session_id" ]]; then
        # Direct session ID provided
        SELECTED_SESSION_ID="$session_id"
        log_good "Selected: ${session_id}"
    else
        # Interactive picker
        print_section "Select Session"
        if ! select_session; then
            return 1
        fi
    fi

    # Write selected session to config
    config_set "selected_session" "$SELECTED_SESSION_ID"
    log_good "Session ${SELECTED_SESSION_ID} selected"

    # Show session details
    echo ""
    local sf
    sf=$(ensure_session_dir "$SELECTED_SESSION_ID")
    if [[ -f "$sf" ]]; then
        local status tasks workspace prompt model
        status=$(jq -r '.status // "?"' "$sf")
        tasks=$(jq -r 'if .task_ids then (.task_ids | join(", ")) else .task_id // "" end' "$sf")
        workspace=$(jq -r '.workspace_id // "—"' "$sf")
        prompt=$(jq -r '.prompt // ""' "$sf" | head -3)
        model=$(jq -r '.model // "—"' "$sf")

        print_kv "Status" "$(echo -e "$(status_badge "$status")")"
        print_kv "Tasks" "$tasks"
        print_kv "Workspace" "$workspace"
        print_kv "Model" "$model"
        echo ""
        echo -e "  ${DIM}Prompt:${NC}"
        echo "$prompt" | head -5 | while IFS= read -r line; do
            echo -e "    ${DIM}${line}${NC}"
        done
    fi
    echo ""
}

cmd_start() {
    _check_jq
    local session_id="${1:-}"
    local cli_override="${2:-}"
    local model_override="${3:-}"

    # If no session given, use selected or launch picker
    if [[ -z "$session_id" ]]; then
        session_id=$(config_get "selected_session")
        if [[ -z "$session_id" ]]; then
            print_section "Start Session"
            log_info "No session selected — launching picker..."
            if ! select_session; then
                return 1
            fi
            session_id="$SELECTED_SESSION_ID"
        fi
    fi

    print_box_header "Starting  ${session_id}"

    # Show what we're about to do
    local sf
    sf=$(ensure_session_dir "$session_id")
    local status tasks cli model
    status=$(jq -r '.status // "?"' "$sf")
    tasks=$(jq -r 'if .task_ids then (.task_ids | join(", ")) else .task_id // "" end' "$sf")
    local session_model
    session_model=$(jq -r '.model // empty' "$sf")

    cli="${cli_override:-$(config_resolve_cli "$session_model")}"
    model="${model_override:-${session_model:-$(config_default_model "$cli")}}"

    print_kv "Session" "$session_id"
    print_kv "Status" "$status"
    print_kv "Tasks" "$tasks"
    print_kv "CLI" "$cli"
    print_kv "Model" "$model"
    print_kv "Timeout" "${AGENT_TIMEOUT}s"
    echo ""

    # Permissions warning
    echo -e "  ${YELLOW}Permissions:${NC}"
    if [[ "$cli" == "claude" ]]; then
        echo -e "    ${BAD}--dangerously-skip-permissions${NC} (full access)"
    else
        echo -e "    ${BAD}--allow-all-tools${NC} (full access)"
    fi
    echo ""

    if ! confirm "Proceed?"; then
        log_dim "Cancelled."
        return 0
    fi

    echo ""

    # Ensure on main branch and pull latest
    ensure_on_main
    git -C "$REPO_ROOT" pull --rebase --quiet 2>/dev/null || true

    # Run session
    run_session "$session_id" "$cli" "$model"
    local rc=$?

    # Clear selected session
    config_set "selected_session" ""

    return $rc
}

cmd_auto() {
    _check_jq
    local poll_interval="${1:-60}"
    local max_sessions="${2:-0}"

    print_box_header "Auto Mode"

    local cli branch
    cli=$(config_get "cli")
    branch=$(config_get "branch")

    print_kv "CLI" "${cli:-claude}"
    print_kv "Branch" "${branch:-main}"
    print_kv "Poll interval" "${poll_interval}s"
    print_kv "Max sessions" "${max_sessions} (0=unlimited)"
    print_kv "Timeout" "${AGENT_TIMEOUT}s"
    echo ""

    # Permissions
    echo -e "  ${YELLOW}Permissions:${NC}"
    echo -e "    ${BAD}Full agent access will be granted${NC}"
    echo ""

    if ! confirm "Start auto-polling?"; then
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
        current_version="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")"
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

# ─── Enqueue / Spawn ──────────────────────────────────────────────

# Shared enqueue logic. Sets ENQUEUED_SESSION_ID on success.
_do_enqueue() {
    _check_jq
    ENQUEUED_SESSION_ID=""

    print_box_header "Enqueue Session"

    # ── Step 1: Pick source (task or PR) ────────────────────────
    echo -e "  ${BRAND}Source${NC}"
    echo ""
    echo -e "    ${CYAN}t)${NC} Task"
    echo -e "    ${CYAN}p)${NC} Pull Request"
    echo ""
    read -p "  Select [t/p]: " source_type

    local task_ids=()
    local pr_number=""
    local pr_branch=""
    local item_title=""
    local template_vars=()

    case "$source_type" in
        t|T|task)
            print_section "Select Task"
            if ! select_task; then
                return 1
            fi
            task_ids+=("$SELECTED_TASK_ID")
            item_title="$SELECTED_TASK_TITLE"
            template_vars+=("TASK_ID=$SELECTED_TASK_ID" "TITLE=$SELECTED_TASK_TITLE")
            ;;
        p|P|pr)
            print_section "Select Pull Request"
            if ! select_pr; then
                return 1
            fi
            pr_number="$SELECTED_PR_NUMBER"
            pr_branch="$SELECTED_PR_BRANCH"
            item_title="$SELECTED_PR_TITLE"
            template_vars+=("PR_NUMBER=$SELECTED_PR_NUMBER" "BRANCH=$SELECTED_PR_BRANCH" "TITLE=$SELECTED_PR_TITLE")

            # Try to extract task IDs from PR title or branch
            local pr_task_ids
            pr_task_ids=$(echo "$SELECTED_PR_TITLE $SELECTED_PR_BRANCH" | grep -oE '[TE]-[0-9]+' | sort -u)
            while IFS= read -r tid; do
                [[ -n "$tid" ]] && task_ids+=("$tid")
            done <<< "$pr_task_ids"
            ;;
        *)
            log_bad "Invalid source type."
            return 1
            ;;
    esac

    # ── Step 2: Select agent workspace ──────────────────────────
    print_section "Agent Workspace"
    if ! select_workspace; then
        return 1
    fi
    local workspace="$SELECTED_WORKSPACE"

    # ── Step 3: Select prompt ───────────────────────────────────
    print_section "Prompt"
    if ! select_prompt "$workspace"; then
        return 1
    fi

    # Render template variables
    local prompt
    prompt=$(render_prompt "$SELECTED_PROMPT" "${template_vars[@]}")

    # Prepend agent role instruction if index.md exists
    local agent_index="${AGENTS_DIR}/${workspace}/index.md"
    if [[ -f "$agent_index" ]]; then
        prompt="Read .patchboard/agents/${workspace}/index.md and confirm that you have read this and understand your role.

${prompt}"
    fi

    # ── Step 4: Select model ────────────────────────────────────
    echo ""
    prompt_choice "Model" "sonnet" "opus" "haiku"
    local model="$REPLY"

    # ── Step 5: Create session file ─────────────────────────────
    local session_id
    local uuid
    uuid=$(generate_uuid)
    session_id="se-${uuid:0:12}"

    local now
    now=$(date -u +%FT%TZ)

    local session_dir="${SESSION_DIR}/${session_id}"
    mkdir -p "$session_dir"

    local task_ids_json
    if [[ ${#task_ids[@]} -gt 0 ]]; then
        task_ids_json=$(printf '%s\n' "${task_ids[@]}" | jq -R . | jq -s .)
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

    # ── Step 6: Summary and confirm ─────────────────────────────
    echo ""
    print_section "Session Summary"
    print_kv "Session" "$session_id"
    print_kv "Source" "$(if [[ -n "$pr_number" ]]; then echo "PR #${pr_number}"; else echo "${task_ids[*]}"; fi)"
    print_kv "Workspace" "$workspace"
    print_kv "Model" "$model"
    print_kv "Tasks" "$(IFS=', '; echo "${task_ids[*]}")"
    echo ""
    echo -e "  ${DIM}Prompt (first 3 lines):${NC}"
    echo "$prompt" | head -3 | while IFS= read -r line; do
        echo -e "    ${DIM}${line}${NC}"
    done
    echo ""

    if ! confirm "Create and push session?"; then
        rm -rf "$session_dir"
        log_dim "Cancelled."
        return 1
    fi

    # ── Step 7: Git commit + push ───────────────────────────────
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
    ENQUEUED_SESSION_ID="$session_id"
    echo ""
    return 0
}

cmd_enqueue() {
    _do_enqueue
}

cmd_spawn() {
    if ! _do_enqueue; then
        return 1
    fi

    local session_id="$ENQUEUED_SESSION_ID"

    # Select and start the newly created session
    config_set "selected_session" "$session_id"
    log_info "Starting session ${session_id}..."
    echo ""
    cmd_start "$session_id"
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
    table_row "select [id]" "Select a session (interactive picker)"
    table_row "start [id]" "Start a session (claim + run agent)"
    table_row "enqueue" "Create a new session from a task or PR"
    table_row "spawn" "Enqueue + select + start a session"
    table_row "auto [int] [max]" "Auto-poll and process queued sessions"
    table_row "cli [name]" "Configure default CLI (claude/copilot/auto)"
    table_row "branch [name]" "Configure main branch"
    table_row "status" "Show settings and session state"
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
    echo -e "    ${DIM}# Quick start: pick and run a session${NC}"
    echo -e "    patchboard start"
    echo ""
    echo -e "    ${DIM}# List tasks, PRs, or sessions${NC}"
    echo -e "    patchboard list tasks"
    echo -e "    patchboard list prs"
    echo -e "    patchboard list sessions 10 queued"
    echo ""
    echo -e "    ${DIM}# Create and start a session from a task/PR${NC}"
    echo -e "    patchboard spawn"
    echo ""
    echo -e "    ${DIM}# Auto-poll every 30s, max 5 sessions${NC}"
    echo -e "    patchboard auto 30 5"
    echo ""
    echo -e "    ${DIM}# Switch CLI to copilot${NC}"
    echo -e "    patchboard cli copilot"
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
        start|run|spawn|sp)   AGENT_NON_INTERACTIVE=false ;;  # interactive by default
        auto|poll)            AGENT_NON_INTERACTIVE=true ;;   # non-interactive by default
    esac
fi

case "$command" in
    version|v)        cmd_version "$@" ;;
    healthcheck|hc)   cmd_healthcheck "$@" ;;
    list|ls)          cmd_list "$@" ;;
    select|sel)       cmd_select "$@" ;;
    start|run)        cmd_start "$@" ;;
    enqueue|eq)       cmd_enqueue "$@" ;;
    spawn|sp)         cmd_spawn "$@" ;;
    auto|poll)        cmd_auto "$@" ;;
    cli)              cmd_cli "$@" ;;
    branch|br)        cmd_branch "$@" ;;
    status|st)        cmd_status "$@" ;;
    help|--help|-h)   cmd_help "$@" ;;
    *)
        log_bad "Unknown command: ${command}"
        echo ""
        cmd_help
        exit 1
        ;;
esac
