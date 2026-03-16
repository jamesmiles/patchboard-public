#!/usr/bin/env bash
#
# patchboard-completions.bash - Tab completion for the patchboard CLI
#
# Source this file in your .bashrc or .bash_profile:
#   source /path/to/.patchboard/tooling/patchboard-completions.bash
#
# Or install via: .patchboard/tooling/install.sh

_patchboard_completions() {
    local cur prev command
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # First argument = command
    if [[ $COMP_CWORD -eq 1 ]]; then
        local commands="version healthcheck list select start auto cli branch status help"
        # Include short aliases
        commands+=" v hc ls sel run poll br st"
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    command="${COMP_WORDS[1]}"

    case "$command" in
        start|run|select|sel)
            # Complete with session IDs
            local session_dir=""
            # Find repo root
            local repo_root
            repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
            if [[ -n "$repo_root" ]]; then
                session_dir="${repo_root}/.patchboard/state/cloud-agents"
            fi

            if [[ -d "$session_dir" ]]; then
                local ids=""
                # Subdirectory layout
                for d in "$session_dir"/se-*/; do
                    [[ -d "$d" ]] || continue
                    local sid
                    sid=$(basename "$d")
                    ids+="$sid "
                done
                # Flat layout
                for f in "$session_dir"/se-*.json; do
                    [[ -f "$f" ]] || continue
                    local sid
                    sid=$(basename "$f" .json)
                    ids+="$sid "
                done
                COMPREPLY=( $(compgen -W "$ids" -- "$cur") )
            fi
            ;;

        cli)
            COMPREPLY=( $(compgen -W "claude copilot auto" -- "$cur") )
            ;;

        branch|br)
            COMPREPLY=( $(compgen -W "main trunk master" -- "$cur") )
            ;;

        list|ls)
            if [[ "$prev" == "list" || "$prev" == "ls" ]]; then
                # First arg = limit (number) or status
                COMPREPLY=( $(compgen -W "10 20 50 queued active failed completed stopped" -- "$cur") )
            elif [[ "$prev" =~ ^[0-9]+$ ]]; then
                # Second arg = status filter
                COMPREPLY=( $(compgen -W "queued active failed completed stopped" -- "$cur") )
            fi
            ;;

        auto|poll)
            if [[ "$prev" == "auto" || "$prev" == "poll" ]]; then
                # Poll interval
                COMPREPLY=( $(compgen -W "10 30 60 120 300" -- "$cur") )
            fi
            ;;
    esac

    return 0
}

# Register completion
complete -F _patchboard_completions patchboard
# Also register for the .bash extension in case called directly
complete -F _patchboard_completions patchboard.bash
