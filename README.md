# git-crumb

A casual cousin of `git stash` that drops snapshots into `refs/crumb` instead
of `refs/stash`, so your throwaway saves never crowd out the stashes you
actually care about.

## Why

- AI-assisted editing rewrites files in seconds. You want a frictionless way to
  snapshot "where I am right now" without thinking.
- `refs/stash` is shared with your deliberate stash workflow. Mixing casual
  saves in drowns the real ones.
- `refs/crumb` is a dedicated ref with its own reflog. Walk it any time with
  `git log -g refs/crumb` (a.k.a. `git log --walk-reflogs refs/crumb`).

Each crumb is a stash-shaped commit (2 or 3 parents), so `git stash show`,
`git stash apply --index`, and `git stash branch` all work on them directly.

## Install

- `git-crumb` — anywhere on `PATH` (e.g. symlink into `~/.local/bin`).
- `completions/git-crumb.bash` — source from `~/.bashrc`.
- `completions/git-crumb.zsh` — symlink as `_git-crumb` into a directory
  on zsh's `fpath`.

## Usage

```
git crumb leave  [-m <msg>]                 Save the current state as a crumb.
git crumb list                              Show the trail, newest first.
git crumb show   [<n>] [<diff-opts>]        Inspect a crumb (default: 0).
git crumb wipe   [<n>]                      Remove one crumb (with arg) or all (no arg).
git crumb branch [--no-save] <name> [<n>]   Promote a crumb to a new branch.
git crumb back   [--no-save] [<n>]          Restore HEAD/index/working tree to a crumb.
```

`<n>` is a reflog index. You can also pass `crumb@{n}`, `refs/crumb@{n}`, or a
raw SHA — anything that resolves to a stash-shaped commit on `refs/crumb`.

`leave` always captures the full state: tracked changes, the index, and
untracked files (`-u`-equivalent), without touching your working tree,
your real index, or `refs/stash`.

`back` and `branch` take an optional `--no-save`. By default both leave a
safety auto-crumb of the current state first, so nothing is silently lost.

### Typical flow

```sh
# Drop a crumb whenever you want a quick checkpoint.
git crumb leave -m "after refactor attempt"

# Keep working, drop more.
vim ...
git crumb leave -m "tried approach A"
vim ...
git crumb leave -m "tried approach B"

# Look back.
git crumb list
# crumb@{0}: tried approach B
# crumb@{1}: tried approach A
# crumb@{2}: after refactor attempt

# Rewind to approach A. The current state is auto-saved first
# (pass --no-save to skip the safety net).
git crumb back 1

# Promote a crumb you like to a real branch.
git crumb branch good-attempt 1
```

## Mapping to `git stash`

| git crumb            | git stash                                              |
|----------------------|--------------------------------------------------------|
| `leave [-m]`         | `push -u [-m]`                                         |
| `list`               | `list`                                                 |
| `show`               | `show`                                                 |
| `wipe <n>`           | `drop`                                                 |
| `wipe`               | `clear`                                                |
| `branch`             | `branch`                                               |
| `back [--no-save]`   | (no direct analogue; manual `reset --hard` + `apply`)  |

## Data model

```
refs/crumb ── reflog ────────────────────────────────────
   │                                                       │
   ▼                                                       ▼
crumb@{0}                                              crumb@{N}
 stash-shaped commit                                       …
 ├ parent[0] = HEAD at leave time
 ├ parent[1] = i_commit  (index → tree → commit)
 ├ parent[2] = u_commit  (untracked → tree → commit, when any)
 └ tree      = working-tree snapshot of tracked changes
```

Each crumb has exactly the structure `git stash push -u` produces, which is
why every stash-aware tool keeps working. Crumbs are assembled by hand with
`git commit-tree` using temporary index files under `.git/`, so your real
index, working tree, and `refs/stash` are never touched.
