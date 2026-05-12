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
    local -a subcommands crumbs branches

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
        '1: :->cmd' \
        '*:: :->args' && ret=0

    case $state in
        cmd)
            _describe -t commands 'git crumb subcommand' subcommands && ret=0
            ;;
        args)
            case $words[1] in
                show)
                    _git-crumb-crumbs && ret=0
                    _arguments '*: :_files' && ret=0
                    ;;
                wipe|back)
                    _git-crumb-crumbs && ret=0
                    [[ $words[1] == back ]] && \
                        _arguments '--no-save[skip the safety auto-leave]' && ret=0
                    ;;
                branch)
                    if (( CURRENT == 2 )); then
                        _alternative \
                            'branches:existing branches (avoid collisions):_git-crumb-branches' \
                            && ret=0
                    else
                        _git-crumb-crumbs && ret=0
                    fi
                    ;;
                leave)
                    _arguments \
                        '(-m --message)'{-m,--message}'[crumb message]:message:' \
                        && ret=0
                    ;;
            esac
            ;;
    esac

    return ret
}

_git-crumb-crumbs() {
    local -a crumbs
    local line
    while IFS= read -r line; do
        crumbs+=("${line}")
    done < <(git log -g --format='%gd:%gs' refs/crumb 2>/dev/null)
    [[ ${#crumbs} -eq 0 ]] && return 1
    _describe -t crumbs 'crumb' crumbs
}

_git-crumb-branches() {
    local -a branches
    branches=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)"})
    _describe -t branches 'branch' branches
}

_git-crumb "$@"
