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

# Ensure config file exists with defaults
config_init() {
    local cfg
    cfg=$(_config_file)
    if [[ ! -f "$cfg" ]]; then
        mkdir -p "$(dirname "$cfg")"
        cat > "$cfg" <<'EOF'
{
  "cli": "claude",
  "branch": "main"
}
EOF
    fi
}

# Read a config key
# Usage: config_get "cli"  →  "claude"
config_get() {
    local key="$1"
    local cfg
    cfg=$(_config_file)
    config_init
    jq -r --arg k "$key" '.[$k] // empty' "$cfg" 2>/dev/null
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
