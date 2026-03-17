#!/usr/bin/env bash
#
# tasks.sh - Task discovery, listing, and selection
#
# Requires: REPO_ROOT set by caller
# Requires: lib/colors.sh sourced

TASK_DIR="${REPO_ROOT}/.patchboard/tasks"

# ─── Task discovery ──────────────────────────────────────────────

# Discover all tasks, optionally filtered by status.
# Parses YAML frontmatter from all task.md files in a single awk pass,
# then uses one jq call to filter and sort.
# Usage: discover_tasks [status_filter]
# Outputs JSON array
discover_tasks() {
    local filter_status="${1:-}"

    if [[ ! -d "$TASK_DIR" ]]; then
        echo "[]"
        return
    fi

    # Collect all task.md files (excluding archived)
    local -a files=()
    for f in "$TASK_DIR"/*/task.md; do
        [[ -e "$f" ]] || continue
        [[ "$f" == *"/.archived/"* ]] && continue
        files+=("$f")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "[]"
        return
    fi

    # Single awk pass: extract YAML frontmatter from all files as JSONL.
    # Handles scalars, quoted strings, inline arrays [...], and multi-line - arrays.
    local jsonl
    jsonl=$(awk '
    BEGIN { in_fm = 0; dashes = 0; first_key = 1; in_array = 0; arr_count = 0 }

    FNR == 1 {
        # Close previous file object if any
        if (NR != FNR || NR != 1) {
            if (in_array) { printf "]"; in_array = 0 }
            if (!first_key) printf "}\n"
        }
        in_fm = 0; dashes = 0; first_key = 1; in_array = 0; arr_count = 0
    }

    /^---[[:space:]]*$/ {
        dashes++
        if (dashes == 1) { in_fm = 1; printf "{"; next }
        if (dashes == 2) {
            if (in_array) { printf "]"; in_array = 0 }
            in_fm = 0; next
        }
    }

    !in_fm { next }

    # Multi-line array item: "- value" or "  - value"
    in_array && /^[[:space:]]*-[[:space:]]+/ {
        val = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", val)
        gsub(/^["'"'"']|["'"'"']$/, "", val)
        gsub(/\\/, "\\\\", val)
        gsub(/"/, "\\\"", val)
        if (arr_count > 0) printf ","
        printf "\"%s\"", val
        arr_count++
        next
    }

    # Key: value line
    /^[a-zA-Z_][a-zA-Z0-9_]*:/ {
        # Close pending array
        if (in_array) { printf "]"; in_array = 0 }

        key = $0; sub(/:.*/, "", key)
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val)

        if (!first_key) printf ","
        first_key = 0

        # Inline array: [item1, item2]
        if (val ~ /^\[.*\]$/) {
            inner = val
            gsub(/^\[|\]$/, "", inner)
            printf "\"%s\":[", key
            if (inner != "") {
                n = split(inner, items, ",")
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
                    gsub(/^["'"'"']|["'"'"']$/, "", items[i])
                    gsub(/\\/, "\\\\", items[i])
                    gsub(/"/, "\\\"", items[i])
                    if (i > 1) printf ","
                    printf "\"%s\"", items[i]
                }
            }
            printf "]"
            next
        }

        # Empty value = start of multi-line array
        if (val == "" || val ~ /^[[:space:]]*$/) {
            printf "\"%s\":[", key
            in_array = 1
            arr_count = 0
            next
        }

        # Scalar
        gsub(/^["'"'"']|["'"'"']$/, "", val)
        gsub(/\\/, "\\\\", val)
        gsub(/"/, "\\\"", val)
        if (val == "null" || val == "~") {
            printf "\"%s\":null", key
        } else {
            printf "\"%s\":\"%s\"", key, val
        }
    }

    END {
        if (in_array) printf "]"
        if (!first_key) printf "}\n"
    }
    ' "${files[@]}" 2>/dev/null)

    # Single jq call: parse JSONL, filter, sort
    if [[ -n "$filter_status" ]]; then
        echo "$jsonl" | jq -s --arg status "$filter_status" \
            '[.[] | select(.status == $status)] | sort_by(.id) | reverse'
    else
        echo "$jsonl" | jq -s 'sort_by(.id) | reverse'
    fi
}

# ─── Task table rendering ────────────────────────────────────────

_setup_task_table() {
    TABLE_WIDTHS=(9 14 5 50 16)
    TABLE_INDENT="  "
}

_task_status_color() {
    local status="$1"
    case "$status" in
        todo)        echo "$DIM" ;;
        ready)       echo "$GOOD" ;;
        in_progress) echo "$CYAN" ;;
        blocked)     echo "$BAD" ;;
        review)      echo "$YELLOW" ;;
        done)        echo "$BRAND" ;;
        *)           echo "$DIM" ;;
    esac
}

# Print tasks as a formatted table.
# Extracts all row data in a single jq call as TSV.
print_task_table() {
    local tasks="$1"
    local count
    count=$(echo "$tasks" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        log_dim "No tasks found."
        return
    fi

    _setup_task_table
    table_header "ID" "STATUS" "PRI" "TITLE" "OWNER"

    # Single jq call: extract all rows as tab-separated lines
    echo "$tasks" | jq -r '.[] | [
        (.id // ""),
        (.status // ""),
        (.priority // ""),
        ((.title // "")[:48]),
        (.owner // "-")
    ] | @tsv' | while IFS=$'\t' read -r _tid _tstatus _tpri _ttitle _towner; do
        local scolor
        scolor=$(_task_status_color "$_tstatus")

        local line=""
        local cols=("$_tid" "$_tstatus" "$_tpri" "$_ttitle" "$_towner")
        for j in "${!cols[@]}"; do
            local w="${TABLE_WIDTHS[$j]:-20}"
            local cell
            cell="$(_fmt_col "${cols[$j]}" "$w")"
            if [[ $j -eq 1 ]]; then
                line+="$(printf "${scolor}%s${NC}" "$cell")"
            else
                line+="$cell"
            fi
        done
        echo -e "${TABLE_INDENT}${line}"
    done

    table_end
    log_dim "${count} task(s)"
}

# ─── Interactive task selector ───────────────────────────────────

# Displays tasks in a numbered table and lets user pick one.
# Sets SELECTED_TASK_ID and SELECTED_TASK_TITLE on success.
# Returns: 0 if selected, 1 if cancelled
select_task() {
    local filter="${1:-}"
    SELECTED_TASK_ID=""
    SELECTED_TASK_TITLE=""

    while true; do
        log_info "Discovering tasks..."
        local tasks
        tasks=$(discover_tasks "$filter")

        local count
        count=$(echo "$tasks" | jq 'length')

        if [[ "$count" -eq 0 ]]; then
            log_warn "No${filter:+ ${filter}} tasks found."
            echo ""
            read -p "  (r)efresh, (a)ll statuses, (q)uit: " action
            case "$action" in
                r|R) continue ;;
                a|A) filter=""; continue ;;
                q|Q|"") return 1 ;;
            esac
            continue
        fi

        echo ""
        _setup_task_table
        TABLE_INDENT="        "
        table_header "ID" "STATUS" "PRI" "TITLE" "OWNER"

        # Pre-extract all rows + IDs in a single jq call
        local -a task_ids=()
        local -a task_titles=()
        local num=0

        echo "$tasks" | jq -r '.[] | [
            (.id // ""),
            (.status // ""),
            (.priority // ""),
            ((.title // "")[:48]),
            (.owner // "-")
        ] | @tsv' | while IFS=$'\t' read -r _tid _tstatus _tpri _ttitle _towner; do
            num=$(( num + 1 ))
            local scolor
            scolor=$(_task_status_color "$_tstatus")

            local line=""
            local cols=("$_tid" "$_tstatus" "$_tpri" "$_ttitle" "$_towner")
            for j in "${!cols[@]}"; do
                local w="${TABLE_WIDTHS[$j]:-20}"
                local cell
                cell="$(_fmt_col "${cols[$j]}" "$w")"
                if [[ $j -eq 1 ]]; then
                    line+="$(printf "${scolor}%s${NC}" "$cell")"
                else
                    line+="$cell"
                fi
            done
            printf "  ${CYAN}%3d)${NC} " "$num"
            echo -e "${line}"
        done

        # Extract IDs and titles for selection (single jq call)
        readarray -t task_ids < <(echo "$tasks" | jq -r '.[].id')
        readarray -t task_titles < <(echo "$tasks" | jq -r '.[].title // ""')

        echo ""
        echo -e "  ${DIM}(r)efresh  (a)ll statuses  (q)uit${NC}"
        read -p "  Select [1-${count}]: " selection

        case "$selection" in
            r|R) continue ;;
            a|A) filter=""; continue ;;
            q|Q|"") return 1 ;;
        esac

        # Number selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 && "$selection" -le "$count" ]]; then
            local idx=$(( selection - 1 ))
            SELECTED_TASK_ID="${task_ids[$idx]}"
            SELECTED_TASK_TITLE="${task_titles[$idx]}"
            log_good "Selected: ${SELECTED_TASK_ID}"
            return 0
        fi

        # Direct task ID (T-XXXX)
        if [[ "$selection" =~ ^[TE]-[0-9]+$ ]]; then
            local i
            for i in "${!task_ids[@]}"; do
                if [[ "${task_ids[$i]}" == "$selection" ]]; then
                    SELECTED_TASK_ID="${task_ids[$i]}"
                    SELECTED_TASK_TITLE="${task_titles[$i]}"
                    log_good "Selected: ${SELECTED_TASK_ID}"
                    return 0
                fi
            done
        fi

        log_bad "Invalid selection: ${selection}"
    done
}
