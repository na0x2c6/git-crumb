# bash completion for git-crumb.
#
# Two forms are supported:
#
#   git crumb <TAB>     handled by git's bash-completion (auto-discovers
#                       `_git_crumb` once this file is sourced)
#   git-crumb <TAB>     handled by the standalone _git_crumb_standalone
#                       function via `complete -F`
#
# Install: source this file from ~/.bashrc, or drop it into
#          /usr/share/bash-completion/completions/git-crumb

_git_crumb_subcommands='leave list show wipe branch back help'

# Print available crumb reflog indices (one per line).
_git_crumb_indices() {
    local n
    n=$(git log -g --format=oneline refs/crumb 2>/dev/null | wc -l)
    if [ "$n" -gt 0 ]; then
        seq 0 $((n - 1))
    fi
}

# Print existing branches (used to warn off collisions for `crumb branch`).
_git_crumb_branches() {
    git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
}

# Called by git-completion when user types `git crumb <TAB>`.
_git_crumb() {
    local subcommand cur prev cword
    cur="${COMP_WORDS[COMP_CWORD]}"
    cword=$COMP_CWORD

    # Find the subcommand position (skip "git crumb")
    local i sub=""
    for (( i = 2; i < cword; i++ )); do
        case "${COMP_WORDS[i]}" in
            -*) ;;
            *) sub="${COMP_WORDS[i]}"; break ;;
        esac
    done

    if [ -z "$sub" ]; then
        COMPREPLY=( $(compgen -W "$_git_crumb_subcommands" -- "$cur") )
        return
    fi

    case "$sub" in
        show|wipe|back)
            COMPREPLY=( $(compgen -W "$(_git_crumb_indices)" -- "$cur") )
            ;;
        branch)
            # First positional after `branch` = new branch name (free input;
            # offer existing branches only as a "don't pick these" reference).
            # Second positional = crumb index.
            local seen=0 j
            for (( j = i + 1; j < cword; j++ )); do
                [[ "${COMP_WORDS[j]}" != -* ]] && seen=$((seen + 1))
            done
            if [ "$seen" -eq 0 ]; then
                COMPREPLY=( $(compgen -W "$(_git_crumb_branches)" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_git_crumb_indices)" -- "$cur") )
            fi
            ;;
        leave)
            case "$cur" in
                -*) COMPREPLY=( $(compgen -W "-m --message" -- "$cur") ) ;;
            esac
            ;;
    esac
}

# Called directly when user types `git-crumb <TAB>`.
_git_crumb_standalone() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local sub=""
    local i
    for (( i = 1; i < COMP_CWORD; i++ )); do
        case "${COMP_WORDS[i]}" in
            -*) ;;
            *) sub="${COMP_WORDS[i]}"; break ;;
        esac
    done

    if [ -z "$sub" ]; then
        COMPREPLY=( $(compgen -W "$_git_crumb_subcommands" -- "$cur") )
        return
    fi

    case "$sub" in
        show|wipe|back)
            COMPREPLY=( $(compgen -W "$(_git_crumb_indices)" -- "$cur") )
            ;;
        branch)
            local seen=0 j
            for (( j = i + 1; j < COMP_CWORD; j++ )); do
                [[ "${COMP_WORDS[j]}" != -* ]] && seen=$((seen + 1))
            done
            if [ "$seen" -eq 0 ]; then
                COMPREPLY=( $(compgen -W "$(_git_crumb_branches)" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_git_crumb_indices)" -- "$cur") )
            fi
            ;;
        leave)
            case "$cur" in
                -*) COMPREPLY=( $(compgen -W "-m --message" -- "$cur") ) ;;
            esac
            ;;
    esac
}

complete -F _git_crumb_standalone git-crumb
