#!/usr/bin/env bash
#
# sessions.sh - Session discovery, listing, and selection
#
# Requires: REPO_ROOT, SESSION_DIR set by caller
# Requires: lib/colors.sh sourced

# ─── Session discovery ─────────────────────────────────────────────

# Discover all sessions, optionally filtered by status
# Usage: discover_sessions [status_filter]
# Outputs JSON array
discover_sessions() {
    local filter_status="${1:-}"

    if [[ ! -d "$SESSION_DIR" ]]; then
        echo "[]"
        return
    fi

    # Bulk-read all session files via jq slurp for performance
    local files=()
    for f in "$SESSION_DIR"/*.json "$SESSION_DIR"/*/session.json; do
        [[ -e "$f" ]] || continue
        files+=("$f")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "[]"
        return
    fi

    local all_sessions
    all_sessions=$(jq -s '.' "${files[@]}" 2>/dev/null || echo "[]")

    if [[ -n "$filter_status" ]]; then
        echo "$all_sessions" | jq --arg st "$filter_status" \
            '[.[] | select(.status == $st and .provider == "self_hosted")]'
    else
        echo "$all_sessions"
    fi
}

# Get the N most recently modified sessions
# Usage: discover_recent [limit]
discover_recent() {
    local limit="${1:-20}"
    local all
    all=$(discover_sessions)
    echo "$all" | jq --argjson n "$limit" 'sort_by(.updated_at // .started_at) | reverse | .[:$n]'
}

# ─── Age formatting ───────────────────────────────────────────────

format_age() {
    local ts="$1"
    [[ -z "$ts" || "$ts" == "null" ]] && { echo "—"; return; }
    local now then diff
    now=$(date -u +%s)
    then=$(date -u -d "${ts}" +%s 2>/dev/null) || { echo "—"; return; }
    diff=$(( now - then ))

    if [[ $diff -lt 60 ]]; then
        echo "${diff}s"
    elif [[ $diff -lt 3600 ]]; then
        echo "$(( diff / 60 ))m"
    elif [[ $diff -lt 86400 ]]; then
        echo "$(( diff / 3600 ))h"
    else
        echo "$(( diff / 86400 ))d"
    fi
}

# ─── Prompt cleanup ──────────────────────────────────────────────
# Extract a meaningful summary from the raw prompt.
# Strips agent boilerplate ("Read .patchboard/agents/...") and YAML
# frontmatter ("--- title: ... ---") to surface the actual intent.
_clean_prompt() {
    local raw="$1"
    local maxlen="${2:-38}"

    # Collapse whitespace
    raw=$(echo "$raw" | tr '\n' ' ' | sed 's/  */ /g')

    # Strip "Read .patchboard/agents/...and confirm that you have read this..."
    # These prompts follow the pattern:
    #   Read .patchboard/agents/ROLE/index.md and confirm ... --- title: X --- REAL CONTENT
    if [[ "$raw" == "Read .patchboard/agents/"* ]]; then
        # Try to find a YAML title after the boilerplate
        local title
        title=$(echo "$raw" | sed -n 's/.*title: *\([^-]*\)---.*/\1/p' | sed 's/ *$//' | head -1)
        if [[ -n "$title" ]]; then
            raw="$title"
        else
            # No title — strip the "Read ... and confirm ... role of X." prefix
            raw=$(echo "$raw" | sed 's/^Read .patchboard\/agents\/[^ ]* and confirm[^.]*\.//' | sed 's/^ *//')
            # If still starts with ---, strip the frontmatter block
            raw="${raw#*---}"
            raw="${raw#*---}"
            raw="${raw# }"
        fi
    fi

    # Strip leading YAML frontmatter "--- title: Foo --- "
    if [[ "$raw" == "--- "* || "$raw" == "---"$'\n'* ]]; then
        local title
        title=$(echo "$raw" | sed -n 's/.*title: *\([^-]*\)---.*/\1/p' | sed 's/ *$//' | head -1)
        if [[ -n "$title" ]]; then
            raw="$title"
        else
            raw="${raw#*---}"       # first ---
            raw="${raw#*---}"       # second ---
            raw="${raw# }"
        fi
    fi

    # Trim and truncate
    raw="${raw# }"
    raw="${raw% }"
    [[ -z "$raw" ]] && raw="(no prompt)"
    if [[ ${#raw} -gt $maxlen ]]; then
        raw="${raw:0:$(( maxlen - 3 ))}..."
    fi
    echo "$raw"
}

# ─── Shared table config ────────────────────────────────────────
# Standard column layout used by both list and select.
#              SESSION   STATUS   TASKS   WORKSPACE           PROMPT                                  AGE
_setup_session_table() {
    TABLE_WIDTHS=(19 11 9 21 40 5)
    TABLE_INDENT="  "
}

# Extract row data from a JSON sessions array at index $1.
# Sets variables: _sid _status _tasks _workspace _prompt _age
_extract_row() {
    local sessions="$1" idx="$2"
    _sid=$(echo "$sessions"    | jq -r ".[$idx].session_id")
    _status=$(echo "$sessions" | jq -r ".[$idx].status")
    _tasks=$(echo "$sessions"  | jq -r "if .[$idx].task_ids then (.[$idx].task_ids | join(\",\")) elif .[$idx].task_id then .[$idx].task_id else \"\" end")
    _workspace=$(echo "$sessions" | jq -r ".[$idx].workspace_id // \"\"")
    local raw_prompt
    raw_prompt=$(echo "$sessions" | jq -r ".[$idx].prompt // \"\"")
    _prompt=$(_clean_prompt "$raw_prompt" 38)
    local ts
    ts=$(echo "$sessions" | jq -r ".[$idx].started_at // .[$idx].updated_at // \"\"")
    _age=$(format_age "$ts")
}

# ─── Session listing ──────────────────────────────────────────────

# Print sessions as a formatted table
# Usage: print_session_table "$json_array"
print_session_table() {
    local sessions="$1"
    local count
    count=$(echo "$sessions" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        log_dim "No sessions found."
        return
    fi

    _setup_session_table
    table_header "SESSION" "STATUS" "TASKS" "WORKSPACE" "PROMPT" "AGE"

    local i=0
    while [[ $i -lt $count ]]; do
        _extract_row "$sessions" "$i"
        table_row_status "$_sid" "$_status" "$_tasks" "$_workspace" "$_prompt" "$_age"
        i=$(( i + 1 ))
    done

    table_end
    log_dim "${count} session(s)"
}

# ─── Interactive session selector ─────────────────────────────────

# Displays sessions in a numbered table and lets user pick one.
# Sets SELECTED_SESSION_ID on success.
# Returns: 0 if selected, 1 if cancelled
select_session() {
    local filter="${1:-queued}"
    SELECTED_SESSION_ID=""

    while true; do
        log_info "Discovering sessions..."
        local sessions
        if [[ "$filter" == "all" ]]; then
            sessions=$(discover_recent 30)
        else
            sessions=$(discover_sessions "$filter")
            if [[ "$filter" == "queued" ]]; then
                if ! echo "$sessions" | jq -e 'all(.[]; (.created_at // "") != "")' >/dev/null; then
                    log_bad "Queued session missing required created_at timestamp."
                    return 1
                fi
                sessions=$(echo "$sessions" | jq 'sort_by(.created_at)')
            else
                sessions=$(echo "$sessions" | jq 'sort_by(.started_at // .updated_at)')
            fi
        fi

        local count
        count=$(echo "$sessions" | jq 'length')

        if [[ "$count" -eq 0 ]]; then
            log_warn "No ${filter} sessions found."
            echo ""
            read -p "  (r)efresh, (a)ll statuses, (q)uit: " action
            case "$action" in
                r|R) continue ;;
                a|A) filter="all"; continue ;;
                q|Q|"") return 1 ;;
            esac
            continue
        fi

        echo ""
        _setup_session_table
        # Shift indent right to make room for "  NN) " prefix (6 chars)
        TABLE_INDENT="        "
        table_header "SESSION" "STATUS" "TASKS" "WORKSPACE" "PROMPT" "AGE"

        local -a session_ids=()
        local i=0
        while [[ $i -lt $count ]]; do
            _extract_row "$sessions" "$i"
            local num=$(( i + 1 ))
            table_row_numbered "$num" "$_sid" "$_status" "$_tasks" "$_workspace" "$_prompt" "$_age"
            session_ids+=("$_sid")
            i=$(( i + 1 ))
        done

        echo ""
        echo -e "  ${DIM}(r)efresh  (a)ll statuses  (q)uit${NC}"
        read -p "  Select [1-${count}]: " selection

        case "$selection" in
            r|R) continue ;;
            a|A) filter="all"; continue ;;
            q|Q|"") return 1 ;;
        esac

        # Number selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 && "$selection" -le "$count" ]]; then
            SELECTED_SESSION_ID="${session_ids[$(( selection - 1 ))]}"
            log_good "Selected: ${SELECTED_SESSION_ID}"
            return 0
        fi

        # Direct session ID
        if [[ "$selection" == se-* || "$selection" == gi-* ]]; then
            local candidate="${SESSION_DIR}/${selection}/session.json"
            if [[ -f "$candidate" ]] || [[ -f "${SESSION_DIR}/${selection}.json" ]]; then
                SELECTED_SESSION_ID="$selection"
                log_good "Selected: ${SELECTED_SESSION_ID}"
                return 0
            fi
        fi

        log_bad "Invalid selection: ${selection}"
    done
}

# ─── Session file helpers ─────────────────────────────────────────

# Ensure session uses subdir layout, return path to session.json
ensure_session_dir() {
    local sid="$1"
    local subdir="${SESSION_DIR}/${sid}"
    mkdir -p "$subdir"
    if [[ -f "${SESSION_DIR}/${sid}.json" && ! -f "${subdir}/session.json" ]]; then
        mv "${SESSION_DIR}/${sid}.json" "${subdir}/session.json"
    fi
    echo "${subdir}/session.json"
}

# Get a field from a session file
# Usage: session_field "se-XXXXX" ".status"
session_field() {
    local sid="$1"
    local field="$2"
    local sf
    sf=$(ensure_session_dir "$sid")
    jq -r "$field // empty" "$sf" 2>/dev/null
}

# List session IDs (for completions)
list_session_ids() {
    local status_filter="${1:-}"
    if [[ ! -d "$SESSION_DIR" ]]; then
        return
    fi

    for f in "$SESSION_DIR"/*/session.json "$SESSION_DIR"/*.json; do
        [[ -e "$f" ]] || continue
        local sid st
        sid=$(jq -r '.session_id // empty' "$f" 2>/dev/null) || continue
        [[ -z "$sid" ]] && continue

        if [[ -n "$status_filter" ]]; then
            st=$(jq -r '.status // empty' "$f" 2>/dev/null)
            [[ "$st" != "$status_filter" ]] && continue
        fi

        echo "$sid"
    done
}
