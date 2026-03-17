#!/usr/bin/env bash
#
# prs.sh - Pull request discovery, listing, and selection
#
# Requires: gh CLI authenticated
# Requires: REPO_ROOT set by caller
# Requires: lib/colors.sh sourced

# ─── PR discovery ────────────────────────────────────────────────

# Discover pull requests via gh CLI
# Usage: discover_prs [state] [limit]
# state: open (default), closed, merged, all
# Outputs JSON array
discover_prs() {
    local state="${1:-open}"
    local limit="${2:-30}"

    if ! command -v gh &>/dev/null; then
        log_bad "gh CLI is required but not installed."
        echo "[]"
        return 1
    fi

    local gh_state="$state"
    [[ "$state" == "all" ]] && gh_state=""

    local args=(pr list --json "number,title,state,headRefName,author,labels,updatedAt" --limit "$limit")
    [[ -n "$gh_state" ]] && args+=(--state "$gh_state")

    local result
    result=$(cd "$REPO_ROOT" && gh "${args[@]}" 2>/dev/null) || {
        log_bad "Failed to fetch PRs (is gh authenticated?)"
        echo "[]"
        return 1
    }

    echo "$result"
}

# ─── PR table rendering ─────────────────────────────────────────

_setup_pr_table() {
    TABLE_WIDTHS=(8 10 28 40 16)
    TABLE_INDENT="  "
}

_pr_state_color() {
    local state="$1"
    case "$state" in
        open)   echo "$GOOD" ;;
        closed) echo "$BAD" ;;
        merged) echo "$BRAND" ;;
        *)      echo "$DIM" ;;
    esac
}

# Print PRs as a formatted table.
# Single jq call extracts all rows as TSV.
print_pr_table() {
    local prs="$1"
    local count
    count=$(echo "$prs" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        log_dim "No pull requests found."
        return
    fi

    _setup_pr_table
    table_header "#" "STATE" "BRANCH" "TITLE" "AUTHOR"

    echo "$prs" | jq -r '.[] | [
        ("#" + (.number | tostring)),
        ((.state // "") | ascii_downcase),
        ((.headRefName // "")[:26]),
        ((.title // "")[:38]),
        (.author.login // "")
    ] | @tsv' | while IFS=$'\t' read -r _pr_id _pr_state _pr_branch _pr_title _pr_author; do
        local scolor
        scolor=$(_pr_state_color "$_pr_state")

        local line=""
        local cols=("$_pr_id" "$_pr_state" "$_pr_branch" "$_pr_title" "$_pr_author")
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
    log_dim "${count} PR(s)"
}

# ─── Interactive PR selector ────────────────────────────────────

# Displays PRs in a numbered table and lets user pick one.
# Sets SELECTED_PR_NUMBER, SELECTED_PR_TITLE, SELECTED_PR_BRANCH on success.
# Returns: 0 if selected, 1 if cancelled
select_pr() {
    local state="${1:-open}"
    SELECTED_PR_NUMBER=""
    SELECTED_PR_TITLE=""
    SELECTED_PR_BRANCH=""

    while true; do
        log_info "Fetching pull requests..."
        local prs
        prs=$(discover_prs "$state")

        local count
        count=$(echo "$prs" | jq 'length')

        if [[ "$count" -eq 0 ]]; then
            log_warn "No ${state} pull requests found."
            echo ""
            read -p "  (r)efresh, (a)ll states, (q)uit: " action
            case "$action" in
                r|R) continue ;;
                a|A) state="all"; continue ;;
                q|Q|"") return 1 ;;
            esac
            continue
        fi

        echo ""
        _setup_pr_table
        TABLE_INDENT="        "
        table_header "#" "STATE" "BRANCH" "TITLE" "AUTHOR"

        local num=0
        echo "$prs" | jq -r '.[] | [
            ("#" + (.number | tostring)),
            ((.state // "") | ascii_downcase),
            ((.headRefName // "")[:26]),
            ((.title // "")[:38]),
            (.author.login // "")
        ] | @tsv' | while IFS=$'\t' read -r _pr_id _pr_state _pr_branch _pr_title _pr_author; do
            num=$(( num + 1 ))
            local scolor
            scolor=$(_pr_state_color "$_pr_state")

            local line=""
            local cols=("$_pr_id" "$_pr_state" "$_pr_branch" "$_pr_title" "$_pr_author")
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

        # Pre-extract selection data (single jq call each)
        local -a pr_nums=()
        local -a pr_titles=()
        local -a pr_branches=()
        readarray -t pr_nums < <(echo "$prs" | jq -r '.[].number')
        readarray -t pr_titles < <(echo "$prs" | jq -r '.[].title // ""')
        readarray -t pr_branches < <(echo "$prs" | jq -r '.[].headRefName // ""')

        echo ""
        echo -e "  ${DIM}(r)efresh  (a)ll states  (q)uit${NC}"
        read -p "  Select [1-${count}]: " selection

        case "$selection" in
            r|R) continue ;;
            a|A) state="all"; continue ;;
            q|Q|"") return 1 ;;
        esac

        # Number selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 && "$selection" -le "$count" ]]; then
            local idx=$(( selection - 1 ))
            SELECTED_PR_NUMBER="${pr_nums[$idx]}"
            SELECTED_PR_TITLE="${pr_titles[$idx]}"
            SELECTED_PR_BRANCH="${pr_branches[$idx]}"
            log_good "Selected: PR #${SELECTED_PR_NUMBER}"
            return 0
        fi

        log_bad "Invalid selection: ${selection}"
    done
}
