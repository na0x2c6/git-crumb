#compdef git-crumb
# zsh completion for git-crumb.
#
# Works for both `git crumb <TAB>` and `git-crumb <TAB>` because zsh's _git
# auto-discovers `_git-<subcommand>` functions in fpath, and #compdef binds
# the file to the standalone command.
#
# Install: add this directory to your fpath before `compinit`, e.g.:
#   fpath=(/path/to/git-crumb/completions $fpath)
#   autoload -Uz compinit && compinit
#
# Or copy/symlink as `_git-crumb` into a directory already in fpath.

_git-crumb() {
    local curcontext="$curcontext" state line ret=1
    local -a subcommands

    subcommands=(
        'leave:save the current state as a crumb'
        'list:show the trail of crumbs'
        'show:inspect a crumb'
        'wipe:remove one crumb (with arg) or all (no arg)'
        'branch:create a branch from a crumb'
        'back:restore HEAD/index/working tree to a crumb'
        'help:show usage'
    )

    _arguments -C \
        '(--trail)--trail=[shared trail name (refs/crumb.<name>)]:trail name:' \
        '1: :->cmd' \
        '*:: :->args' && ret=0

    case $state in
        cmd)
            _describe -t commands 'git crumb subcommand' subcommands && ret=0
            ;;
        args)
            case $words[1] in
                show)
                    _arguments \
                        '--trail=[shared trail name]:trail name:' \
                        '*: :_git-crumb-crumbs-or-files' && ret=0
                    ;;
                wipe)
                    _arguments \
                        '--trail=[shared trail name]:trail name:' \
                        '*: :_git-crumb-crumbs' && ret=0
                    ;;
                back)
                    _arguments \
                        '--no-save[skip the safety auto-leave]' \
                        '--trail=[shared trail name]:trail name:' \
                        '*: :_git-crumb-crumbs' && ret=0
                    ;;
                branch)
                    if (( CURRENT == 2 )); then
                        _alternative \
                            'branches:existing branches (avoid collisions):_git-crumb-branches' \
                            && ret=0
                    else
                        _arguments \
                            '--no-save[skip the safety auto-leave]' \
                            '--trail=[shared trail name]:trail name:' \
                            '*: :_git-crumb-crumbs' && ret=0
                    fi
                    ;;
                leave)
                    _arguments \
                        '(-m --message)'{-m,--message}'[crumb message]:message:' \
                        '--trail=[shared trail name]:trail name:' \
                        && ret=0
                    ;;
                list)
                    _arguments \
                        '--trail=[shared trail name]:trail name:' \
                        && ret=0
                    ;;
            esac
            ;;
    esac

    return ret
}

# Inspect $words for --trail / --trail=<name> and print the active ref.
_git-crumb-active-ref() {
    local i w
    for (( i = 1; i <= ${#words[@]}; i++ )); do
        w="${words[i]}"
        case "$w" in
            --trail=*) print -- "refs/crumb.${w#--trail=}"; return ;;
            --trail)
                if [[ -n "${words[i + 1]:-}" ]]; then
                    print -- "refs/crumb.${words[i + 1]}"
                    return
                fi
                ;;
        esac
    done
    print -- 'refs/worktree/crumb'
}

_git-crumb-crumbs() {
    local -a crumbs
    local ref line
    ref=$(_git-crumb-active-ref)
    while IFS= read -r line; do
        crumbs+=("${line}")
    done < <(git log -g --format='%gd:%gs' "$ref" 2>/dev/null)
    [[ ${#crumbs} -eq 0 ]] && return 1
    _describe -t crumbs 'crumb' crumbs
}

# show accepts diff-opts after the crumb selector; fall through to files.
_git-crumb-crumbs-or-files() {
    _alternative \
        'crumbs:crumb:_git-crumb-crumbs' \
        'files:file:_files'
}

_git-crumb-branches() {
    local -a branches
    branches=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)"})
    _describe -t branches 'branch' branches
}

_git-crumb "$@"
