#!/usr/bin/env bash
#
# config.sh - Configuration management for patchboard CLI
#
# Stores persistent local settings in .patchboard/tooling/state/config.json
# This directory is gitignored — config is per-machine, not shared.

# Requires: REPO_ROOT set by caller

_config_file() {
    echo "${REPO_ROOT}/.patchboard/tooling/state/config.json"
}

_config_log_init() {
    local message="$1"
    if declare -F log_warn >/dev/null 2>&1; then
        log_warn "$message" >&2
    else
        echo "patchboard: ${message}" >&2
    fi
}

_config_log_error() {
    local message="$1"
    if declare -F log_bad >/dev/null 2>&1; then
        log_bad "$message" >&2
    else
        echo "patchboard: ${message}" >&2
    fi
}

config_detect_remote_default_branch() {
    local remote_head
    remote_head=$(git -C "$REPO_ROOT" remote show origin 2>/dev/null | sed -n 's/^  HEAD branch: //p' | head -n 1)
    if [[ -n "$remote_head" && "$remote_head" != "(unknown)" ]]; then
        printf '%s\n' "$remote_head"
        return 0
    fi

    remote_head=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [[ -n "$remote_head" ]]; then
        printf '%s\n' "${remote_head#origin/}"
        return 0
    fi

    return 1
}

config_detect_default_branch() {
    local remote_head
    if remote_head=$(config_detect_remote_default_branch); then
        printf '%s\n' "$remote_head"
        return 0
    fi

    local current_branch
    current_branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
    if [[ -n "$current_branch" ]]; then
        printf '%s\n' "$current_branch"
        return 0
    fi

    local candidate
    for candidate in main master trunk; do
        if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/${candidate}" \
            || git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/${candidate}"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    printf '%s\n' "main"
}

# Ensure config file exists with defaults
config_init() {
    local cfg
    cfg=$(_config_file)
    if [[ ! -f "$cfg" ]]; then
        local default_branch
        default_branch=$(config_detect_default_branch)
        mkdir -p "$(dirname "$cfg")"
        cat > "$cfg" <<EOF
{
  "cli": "claude",
  "branch": "${default_branch}"
}
EOF
        _config_log_init "Project config not found. Initializing local config and using default branch '${default_branch}'."
    fi
}

# Read a config key
# Usage: config_get "cli"  →  "claude"
config_get() {
    local key="$1"
    local cfg
    cfg=$(_config_file)
    config_init

    local value
    if ! value=$(jq -r --arg k "$key" '.[$k] // empty' "$cfg" 2>&1); then
        _config_log_error "Failed to read config '${key}' from ${cfg}: ${value}"
        return 1
    fi

    printf '%s\n' "$value"
}

config_get_required() {
    local key="$1"
    local cfg
    cfg=$(_config_file)
    config_init

    local value
    if ! value=$(jq -er --arg k "$key" '.[$k] // error("missing config key")' "$cfg" 2>&1); then
        _config_log_error "Failed to read required config '${key}' from ${cfg}: ${value}"
        return 1
    fi

    printf '%s\n' "$value"
}

config_resolve_branch() {
    if [[ -n "${PATCHBOARD_BRANCH_OVERRIDE:-}" ]]; then
        printf '%s\n' "$PATCHBOARD_BRANCH_OVERRIDE"
        return 0
    fi

    config_get_required "branch"
}

# Set a config key
# Usage: config_set "cli" "copilot"
config_set() {
    local key="$1"
    local value="$2"
    local cfg
    cfg=$(_config_file)
    config_init
    local tmp="${cfg}.tmp"
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
}

# Get CLI with session model preference fallback
# If cli is "auto", checks session model preference to pick claude/copilot
# Usage: config_resolve_cli [session_model]
config_resolve_cli() {
    local session_model="${1:-}"
    local cli
    cli=$(config_get "cli")

    if [[ "$cli" == "auto" && -n "$session_model" ]]; then
        case "$session_model" in
            *claude*|sonnet|opus|haiku)
                echo "claude"
                ;;
            *gpt*|*codex*|*gemini*)
                echo "copilot"
                ;;
            *)
                echo "claude"
                ;;
        esac
    else
        echo "${cli:-claude}"
    fi
}

# Get the default model for a given CLI
config_default_model() {
    local cli="${1:-claude}"
    case "$cli" in
        claude) echo "sonnet" ;;
        copilot) echo "claude-sonnet-4.6" ;;
        *) echo "sonnet" ;;
    esac
}
