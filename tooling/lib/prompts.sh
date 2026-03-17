#!/usr/bin/env bash
#
# prompts.sh - Agent prompt template discovery, selection, and rendering
#
# Requires: REPO_ROOT set by caller
# Requires: lib/colors.sh sourced

AGENTS_DIR="${REPO_ROOT}/.patchboard/agents"

# ─── Agent workspace discovery ───────────────────────────────────

# Discover available agent workspaces
# Outputs newline-separated workspace names
discover_workspaces() {
    if [[ ! -d "$AGENTS_DIR" ]]; then
        return
    fi

    for dir in "$AGENTS_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        # Skip special directories
        [[ "$name" == "prompts" || "$name" == "_templates" ]] && continue
        echo "$name"
    done
}

# Interactive workspace selector
# Sets SELECTED_WORKSPACE on success.
# Returns: 0 if selected, 1 if cancelled
select_workspace() {
    SELECTED_WORKSPACE=""

    local -a workspaces=()
    while IFS= read -r ws; do
        [[ -n "$ws" ]] && workspaces+=("$ws")
    done < <(discover_workspaces)

    if [[ ${#workspaces[@]} -eq 0 ]]; then
        log_warn "No agent workspaces found in .patchboard/agents/"
        echo ""
        read -p "  Enter workspace name (or q to quit): " input
        if [[ -z "$input" || "$input" == "q" || "$input" == "Q" ]]; then
            return 1
        fi
        SELECTED_WORKSPACE="$input"
        return 0
    fi

    echo ""
    echo -e "  ${BRAND}Select Agent Workspace${NC}"
    echo ""

    local i
    for i in "${!workspaces[@]}"; do
        local num=$(( i + 1 ))
        local ws="${workspaces[$i]}"
        local desc=""
        # Try to read first line of index.md for description
        local index_file="${AGENTS_DIR}/${ws}/index.md"
        if [[ -f "$index_file" ]]; then
            desc=$(sed -n '/^#/{s/^#\+ *//;p;q;}' "$index_file" 2>/dev/null)
        fi
        if [[ -n "$desc" ]]; then
            echo -e "    ${CYAN}${num})${NC} ${ws}  ${DIM}— ${desc}${NC}"
        else
            echo -e "    ${CYAN}${num})${NC} ${ws}"
        fi
    done
    echo ""
    read -p "  Select [1-${#workspaces[@]}]: " selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 && "$selection" -le "${#workspaces[@]}" ]]; then
        SELECTED_WORKSPACE="${workspaces[$(( selection - 1 ))]}"
        log_good "Workspace: ${SELECTED_WORKSPACE}"
        return 0
    fi

    # Allow typing workspace name directly
    if [[ -n "$selection" && "$selection" != "q" && "$selection" != "Q" ]]; then
        SELECTED_WORKSPACE="$selection"
        log_good "Workspace: ${SELECTED_WORKSPACE}"
        return 0
    fi

    return 1
}

# ─── Prompt template discovery ───────────────────────────────────

# Discover prompt templates for a workspace
# Checks workspace-specific prompts/ and shared prompts/
# Outputs array of file paths
discover_prompts() {
    local workspace="${1:-}"
    local -a found=()

    # Workspace-specific prompts
    if [[ -n "$workspace" && -d "${AGENTS_DIR}/${workspace}/prompts" ]]; then
        for f in "${AGENTS_DIR}/${workspace}/prompts"/*.md; do
            [[ -e "$f" ]] && found+=("$f")
        done
    fi

    # Shared prompts
    if [[ -d "${AGENTS_DIR}/prompts" ]]; then
        for f in "${AGENTS_DIR}/prompts"/*.md; do
            [[ -e "$f" ]] && found+=("$f")
        done
    fi

    printf '%s\n' "${found[@]}"
}

# Extract a title from a prompt template file
# Checks YAML frontmatter title, then first # heading, then filename
_prompt_title() {
    local file="$1"
    local name
    name=$(basename "$file" .md)

    # Try YAML frontmatter title
    local title
    title=$(sed -n '/^---$/,/^---$/{ /^title:/{ s/^title:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//; p; q; } }' "$file" 2>/dev/null)
    if [[ -n "$title" ]]; then
        echo "$title"
        return
    fi

    # Try first heading
    title=$(sed -n '/^#/{s/^#\+ *//;p;q;}' "$file" 2>/dev/null)
    if [[ -n "$title" ]]; then
        echo "$title"
        return
    fi

    # Fallback to filename
    echo "$name"
}

# Interactive prompt selector
# Sets SELECTED_PROMPT (the full prompt text) on success.
# Returns: 0 if selected, 1 if cancelled
select_prompt() {
    local workspace="${1:-}"
    SELECTED_PROMPT=""

    local -a prompt_files=()
    local -a prompt_titles=()

    while IFS= read -r pf; do
        [[ -n "$pf" ]] || continue
        prompt_files+=("$pf")
        prompt_titles+=("$(_prompt_title "$pf")")
    done < <(discover_prompts "$workspace")

    echo ""
    echo -e "  ${BRAND}Select Prompt${NC}"
    echo ""

    local i
    local has_templates=false
    if [[ ${#prompt_files[@]} -gt 0 ]]; then
        has_templates=true
        for i in "${!prompt_files[@]}"; do
            local num=$(( i + 1 ))
            local source_label=""
            if [[ "${prompt_files[$i]}" == *"/agents/prompts/"* ]]; then
                source_label=" ${DIM}(shared)${NC}"
            fi
            echo -e "    ${CYAN}${num})${NC} ${prompt_titles[$i]}${source_label}"
        done
    fi

    local custom_num=$(( ${#prompt_files[@]} + 1 ))
    echo -e "    ${CYAN}${custom_num})${NC} ${YELLOW}Custom prompt${NC}"
    echo ""

    local max_choice=$custom_num
    read -p "  Select [1-${max_choice}]: " selection

    # Custom prompt
    if [[ "$selection" == "$custom_num" || ( "$selection" =~ ^[cC] ) ]]; then
        echo ""
        echo -e "  ${DIM}Enter prompt (end with empty line):${NC}"
        local prompt_text=""
        while IFS= read -r line; do
            [[ -z "$line" ]] && break
            [[ -n "$prompt_text" ]] && prompt_text+=$'\n'
            prompt_text+="$line"
        done
        if [[ -z "$prompt_text" ]]; then
            log_bad "Empty prompt."
            return 1
        fi
        SELECTED_PROMPT="$prompt_text"
        log_good "Custom prompt set."
        return 0
    fi

    # Template selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 && "$selection" -le "${#prompt_files[@]}" ]]; then
        local idx=$(( selection - 1 ))
        local file="${prompt_files[$idx]}"
        # Read file content, strip YAML frontmatter
        local content
        content=$(cat "$file")
        if [[ "$content" == ---* ]]; then
            content=$(printf '%s\n' "$content" | awk '/^---$/ { count++; next } count >= 2 { print }')
        fi
        SELECTED_PROMPT="$content"
        log_good "Prompt: ${prompt_titles[$idx]}"
        return 0
    fi

    log_bad "Invalid selection."
    return 1
}

# ─── Template variable substitution ─────────────────────────────

# Replace {{VAR}} placeholders in a prompt string
# Usage: render_prompt "$template" TASK_ID=T-0001 PR_NUMBER=42 BRANCH=feature/foo TITLE="My task"
render_prompt() {
    local template="$1"
    shift

    local result="$template"
    for arg in "$@"; do
        local key="${arg%%=*}"
        local val="${arg#*=}"
        result="${result//\{\{${key}\}\}/$val}"
    done

    echo "$result"
}
