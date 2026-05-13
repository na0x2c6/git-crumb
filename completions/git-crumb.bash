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

# Inspect the current command line for --trail / --trail=<name> and print
# the ref the user is targeting. Defaults to refs/worktree/crumb.
_git_crumb_active_ref() {
    local i words
    words=("$@")
    for (( i = 0; i < ${#words[@]}; i++ )); do
        case "${words[i]}" in
            --trail=*) printf 'refs/crumb.%s\n' "${words[i]#--trail=}"; return ;;
            --trail)
                if [ -n "${words[i + 1]:-}" ]; then
                    printf 'refs/crumb.%s\n' "${words[i + 1]}"
                    return
                fi
                ;;
        esac
    done
    printf 'refs/worktree/crumb\n'
}

# Print available crumb reflog indices (one per line) for the active ref.
_git_crumb_indices() {
    local ref n
    ref=$(_git_crumb_active_ref "${COMP_WORDS[@]}")
    n=$(git log -g --format=oneline "$ref" 2>/dev/null | wc -l)
    if [ "$n" -gt 0 ]; then
        seq 0 $((n - 1))
    fi
}

# Print existing branches (used to warn off collisions for `crumb branch`).
_git_crumb_branches() {
    git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
}

_git_crumb_dispatch() {
    local cur prev sub i seen j start
    cur="${COMP_WORDS[COMP_CWORD]}"
    start="$1"  # first index *after* "git crumb" / "git-crumb"

    # If the user is in the middle of typing --trail=<value>, offer no values
    # (free input). If they're on a bare --trail, leave it to the user.
    case "$cur" in
        --trail=*)
            return ;;
    esac

    # Find the subcommand position, ignoring options. --trail consumes its
    # argument when written as `--trail name`.
    sub=""
    i=$start
    while (( i < COMP_CWORD )); do
        case "${COMP_WORDS[i]}" in
            --trail) (( i += 2 )); continue ;;
            --trail=*) (( i += 1 )); continue ;;
            -*) (( i += 1 )); continue ;;
            *) sub="${COMP_WORDS[i]}"; break ;;
        esac
        (( i += 1 ))
    done

    if [ -z "$sub" ]; then
        if [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "--trail --trail=" -- "$cur") )
        else
            COMPREPLY=( $(compgen -W "$_git_crumb_subcommands" -- "$cur") )
        fi
        return
    fi

    case "$sub" in
        show|wipe|back)
            if [[ "$cur" == -* ]]; then
                local opts="--trail --trail="
                [[ "$sub" == back ]] && opts="$opts --no-save"
                COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_git_crumb_indices)" -- "$cur") )
            fi
            ;;
        branch)
            # First non-option positional after `branch` = new branch name
            # (free input; existing branches are offered as a "don't pick
            # these" reference). Second positional = crumb index.
            seen=0
            j=$((i + 1))
            while (( j < COMP_CWORD )); do
                case "${COMP_WORDS[j]}" in
                    --trail) (( j += 2 )); continue ;;
                    --trail=*|-*) (( j += 1 )); continue ;;
                esac
                seen=$((seen + 1))
                (( j += 1 ))
            done
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--no-save --trail --trail=" -- "$cur") )
            elif [ "$seen" -eq 0 ]; then
                COMPREPLY=( $(compgen -W "$(_git_crumb_branches)" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_git_crumb_indices)" -- "$cur") )
            fi
            ;;
        leave)
            case "$cur" in
                -*) COMPREPLY=( $(compgen -W "-m --message --trail --trail=" -- "$cur") ) ;;
            esac
            ;;
        list)
            case "$cur" in
                -*) COMPREPLY=( $(compgen -W "--trail --trail=" -- "$cur") ) ;;
            esac
            ;;
    esac
}

# Called by git-completion when user types `git crumb <TAB>`.
_git_crumb() {
    _git_crumb_dispatch 2
}

# Called directly when user types `git-crumb <TAB>`.
_git_crumb_standalone() {
    _git_crumb_dispatch 1
}

complete -F _git_crumb_standalone git-crumb
