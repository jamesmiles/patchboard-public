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
        local commands="version healthcheck list select start enqueue spawn auto cli branch status upgrade help"
        # Include short aliases
        commands+=" v hc ls sel run eq sp poll br st up"
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
                # First arg = subcommand or legacy limit/status
                COMPREPLY=( $(compgen -W "sessions tasks prs 10 20 50 queued active failed completed stopped" -- "$cur") )
            elif [[ "$prev" == "sessions" || "$prev" == "s" ]]; then
                COMPREPLY=( $(compgen -W "10 20 50 queued active failed completed stopped" -- "$cur") )
            elif [[ "$prev" == "tasks" || "$prev" == "t" ]]; then
                COMPREPLY=( $(compgen -W "10 20 50 todo ready in_progress blocked review done" -- "$cur") )
            elif [[ "$prev" == "prs" || "$prev" == "pr" || "$prev" == "pulls" ]]; then
                COMPREPLY=( $(compgen -W "10 20 50 open closed merged all" -- "$cur") )
            elif [[ "$prev" =~ ^[0-9]+$ ]]; then
                # Second arg after limit = status/state filter
                local subcmd="${COMP_WORDS[2]}"
                case "$subcmd" in
                    tasks|t)
                        COMPREPLY=( $(compgen -W "todo ready in_progress blocked review done" -- "$cur") )
                        ;;
                    prs|pr|pulls)
                        COMPREPLY=( $(compgen -W "open closed merged all" -- "$cur") )
                        ;;
                    *)
                        COMPREPLY=( $(compgen -W "queued active failed completed stopped" -- "$cur") )
                        ;;
                esac
            fi
            ;;

        auto|poll)
            if [[ "$prev" == "auto" || "$prev" == "poll" ]]; then
                # Poll interval
                COMPREPLY=( $(compgen -W "10 30 60 120 300" -- "$cur") )
            fi
            ;;

        upgrade|up)
            COMPREPLY=( $(compgen -W "force" -- "$cur") )
            ;;
    esac

    return 0
}

# Register completion
complete -F _patchboard_completions patchboard
# Also register for the .bash extension in case called directly
complete -F _patchboard_completions patchboard.bash
