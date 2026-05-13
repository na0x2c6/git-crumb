#!/usr/bin/env bats
# Tests for git-crumb. Run with: bats test/

setup() {
    GIT_CRUMB_BIN="${BATS_TEST_DIRNAME}/../git-crumb"
    [ -x "$GIT_CRUMB_BIN" ] || skip "git-crumb not executable"

    REPO_DIR="$(mktemp -d)"
    cd "$REPO_DIR"

    git init -q .
    git config user.email "t@t"
    git config user.name "t"
    git commit -q --allow-empty -m init
    echo orig > a.txt
    git add a.txt
    git commit -q -m a

    # Make crumb invokable as both `git-crumb` and `git crumb`
    PATH="$(dirname "$GIT_CRUMB_BIN"):$PATH"
    export PATH
}

teardown() {
    if [ -n "${REPO_DIR:-}" ] && [ -d "$REPO_DIR" ]; then
        # Best-effort cleanup of any linked worktrees registered under REPO_DIR.
        local wt
        while IFS= read -r wt; do
            [ -z "$wt" ] && continue
            [ "$wt" = "$REPO_DIR" ] && continue
            rm -rf -- "$wt"
        done < <(cd "$REPO_DIR" 2>/dev/null && \
            git worktree list --porcelain 2>/dev/null \
            | awk '/^worktree /{print $2}')
        rm -rf "$REPO_DIR"
    fi
}

# helper: count parents of a commit
parents_of() {
    git rev-list --parents -n1 "$1" | awk '{print NF - 1}'
}

# --- T1 ----------------------------------------------------------------------
@test "leave on clean working tree is a no-op and creates no ref" {
    run git crumb leave
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes to crumb"* ]]
    run git rev-parse --verify refs/worktree/crumb
    [ "$status" -ne 0 ]
}

# --- T2 ----------------------------------------------------------------------
@test "leave with only tracked changes creates 2-parent crumb" {
    echo modified > a.txt
    run git crumb leave -m "tracked-only"
    [ "$status" -eq 0 ]

    git rev-parse --verify refs/worktree/crumb
    [ "$(parents_of refs/worktree/crumb)" -eq 2 ]

    # working tree and index unchanged
    run git status --porcelain
    [[ "$output" == " M a.txt" ]]

    # refs/stash untouched
    run git rev-parse --verify refs/stash
    [ "$status" -ne 0 ]
}

# --- T3 ----------------------------------------------------------------------
@test "leave with untracked creates 3-parent crumb; parent[2] tree has only untracked" {
    echo new > u.txt
    run git crumb leave -m "untracked"
    [ "$status" -eq 0 ]
    [ "$(parents_of refs/worktree/crumb)" -eq 3 ]

    # parent[2] tree should contain u.txt only
    run git ls-tree -r --name-only "refs/worktree/crumb^3"
    [ "$output" = "u.txt" ]
}

# --- T4 ----------------------------------------------------------------------
@test "leave captures staged + tracked + untracked in correct components" {
    echo modified > a.txt
    echo staged   > b.txt
    git add b.txt
    echo untracked > u.txt

    git crumb leave -m mixed
    [ "$(parents_of refs/worktree/crumb)" -eq 3 ]

    # parent[1]^{tree} should match the index BEFORE leave (a.txt orig + b.txt staged)
    run git ls-tree -r --name-only refs/worktree/crumb^2
    [[ "$output" == *"a.txt"* ]]
    [[ "$output" == *"b.txt"* ]]
    [[ "$output" != *"u.txt"* ]]

    # parent[2]^{tree} should be just u.txt
    run git ls-tree -r --name-only refs/worktree/crumb^3
    [ "$output" = "u.txt" ]

    # main tree has tracked changes; untracked stays in parent[2] only
    # (matches `git stash push -u` layout)
    run git ls-tree -r --name-only refs/worktree/crumb
    [[ "$output" == *"a.txt"* ]]
    [[ "$output" == *"b.txt"* ]]
    [[ "$output" != *"u.txt"* ]]

    # a.txt content in main tree = modified
    blob=$(git ls-tree refs/worktree/crumb a.txt | awk '{print $3}')
    [ "$(git cat-file -p "$blob")" = "modified" ]
}

# --- T5 ----------------------------------------------------------------------
@test "leave leaves no temp index files behind" {
    echo x > a.txt
    echo y > u.txt
    git crumb leave -m clean
    run bash -c 'ls .git/crumb-* 2>/dev/null | head -1'
    [ -z "$output" ]
}

# --- T6 ----------------------------------------------------------------------
@test "list shows crumbs newest-first in crumb@{n} format" {
    echo 1 > a.txt; git crumb leave -m first
    echo 2 > a.txt; git crumb leave -m second
    echo 3 > a.txt; git crumb leave -m third

    run git crumb list
    [ "$status" -eq 0 ]

    # 3 lines, top is third
    [ "$(echo "$output" | wc -l)" -eq 3 ]
    [[ "$(echo "$output" | sed -n 1p)" == "crumb@{0}: third"  ]]
    [[ "$(echo "$output" | sed -n 2p)" == "crumb@{1}: second" ]]
    [[ "$(echo "$output" | sed -n 3p)" == "crumb@{2}: first"  ]]
}

# --- T7 ----------------------------------------------------------------------
@test "show accepts 0, crumb@{0}, refs/worktree/crumb@{0}, and raw SHA" {
    echo modified > a.txt
    git crumb leave -m t7

    expected_sha=$(git rev-parse refs/worktree/crumb)

    for ref in 0 'crumb@{0}' 'refs/worktree/crumb@{0}' "$expected_sha"; do
        run git crumb show "$ref" --stat
        [ "$status" -eq 0 ]
        [[ "$output" == *"a.txt"* ]]
    done
}

# --- T8 ----------------------------------------------------------------------
@test "wipe <n> drops one entry, others shift up" {
    echo 1 > a.txt; git crumb leave -m first
    echo 2 > a.txt; git crumb leave -m second
    echo 3 > a.txt; git crumb leave -m third

    # crumb@{1} is "second"; wipe it
    run git crumb wipe 1
    [ "$status" -eq 0 ]

    run git crumb list
    [ "$(echo "$output" | wc -l)" -eq 2 ]
    [[ "$(echo "$output" | sed -n 1p)" == "crumb@{0}: third" ]]
    [[ "$(echo "$output" | sed -n 2p)" == "crumb@{1}: first" ]]
}

# --- T9 ----------------------------------------------------------------------
@test "wipe (no arg) removes ref and reflog file" {
    echo x > a.txt; git crumb leave -m a
    echo y > a.txt; git crumb leave -m b

    run git crumb wipe
    [ "$status" -eq 0 ]

    run git rev-parse --verify refs/worktree/crumb
    [ "$status" -ne 0 ]
    [ ! -e .git/logs/refs/worktree/crumb ]

    run git crumb list
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- T10 ---------------------------------------------------------------------
@test "branch creates new branch with untracked restored and removes the crumb" {
    echo modified > a.txt
    echo new > u.txt
    git crumb leave -m for-branch

    # Reset the working tree to a clean state (clean branch start)
    git checkout -q -- a.txt
    rm -f u.txt

    run git crumb branch --no-save recovered 0
    [ "$status" -eq 0 ]

    run git branch
    [[ "$output" == *"recovered"* ]]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "recovered" ]

    # u.txt should be restored as untracked
    [ -f u.txt ]
    run git status --porcelain u.txt
    [[ "$output" == "?? u.txt" ]]

    # crumb should be gone
    run git rev-parse --verify refs/worktree/crumb
    [ "$status" -ne 0 ]
}

# --- T10b (auto-save variant) ------------------------------------------------
@test "branch auto-leaves dirty working tree then drops the right reflog entry" {
    echo a1 > a.txt; git crumb leave -m "older"
    echo a2 > a.txt; git crumb leave -m "newer"

    # The crumb we want to promote is crumb@{1} = "older"
    older_sha=$(git rev-parse refs/worktree/crumb@{1})

    # Dirty working tree so that branch must auto-leave + reset+clean to proceed
    echo dirty > a.txt
    echo dirty > newfile.txt

    run git crumb branch promoted 1
    [ "$status" -eq 0 ]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "promoted" ]

    # Trail should now be: [auto-crumb, "newer"] — "older" was dropped.
    run git crumb list
    [ "$(echo "$output" | wc -l)" -eq 2 ]
    [[ "$(echo "$output" | sed -n 1p)" == *"auto-crumb before branch promoted"* ]]
    [[ "$(echo "$output" | sed -n 2p)" == *"newer"* ]]

    # And the dropped entry is not in the reflog anywhere.
    run git log -g --format=%H refs/worktree/crumb
    [[ "$output" != *"$older_sha"* ]]
}

# --- T11 ---------------------------------------------------------------------
@test "back restores HEAD/index/working-tree/untracked exactly" {
    echo modified > a.txt
    echo staged > b.txt; git add b.txt
    echo untracked > u.txt
    git crumb leave -m snapshot

    # Now move HEAD forward and totally change the working tree
    git commit -q -am "diverging commit"
    echo wholly-different > a.txt
    rm -f u.txt b.txt

    # back to the crumb
    run git crumb back 0 --no-save
    [ "$status" -eq 0 ]

    [ "$(cat a.txt)" = "modified" ]
    [ "$(cat u.txt)" = "untracked" ]
    [ "$(cat b.txt)" = "staged" ]
    run git status --porcelain
    [[ "$output" == *" M a.txt"* ]]
    [[ "$output" == *"A  b.txt"* ]]
    [[ "$output" == *"?? u.txt"* ]]
}

# --- T12 ---------------------------------------------------------------------
@test "back auto-leaves current dirty state before restoring" {
    echo first > a.txt
    git crumb leave -m original-snapshot

    # Make a different dirty state
    echo different > a.txt

    run git crumb back 0
    [ "$status" -eq 0 ]

    # crumb@{0} should now be the auto-crumb, crumb@{1} = original
    run git crumb list
    [ "$(echo "$output" | wc -l)" -eq 2 ]
    [[ "$(echo "$output" | sed -n 1p)" == *"auto-crumb before back"* ]]
    [[ "$(echo "$output" | sed -n 2p)" == *"original-snapshot"* ]]

    # Restored state should match original
    [ "$(cat a.txt)" = "first" ]
}

# --- T13 ---------------------------------------------------------------------
@test "back --no-save skips the auto-leave safety" {
    echo first > a.txt
    git crumb leave -m only

    echo about-to-be-lost > a.txt

    run git crumb back 0 --no-save
    [ "$status" -eq 0 ]

    run git crumb list
    [ "$(echo "$output" | wc -l)" -eq 1 ]
    [[ "$output" == *"only"* ]]
}

# --- T15 (regression) -------------------------------------------------------
@test "back works when working tree already has untracked files matching crumb" {
    # Create a crumb with untracked u.txt
    echo modified > a.txt
    echo first-untracked > u.txt
    git crumb leave -m has-untracked

    # Diverge: commit the tracked change, leaving u.txt untracked but different
    git commit -q -am "tracked diverged"
    echo CURRENT > u.txt   # untracked file overlaps with the crumb's u_commit

    # Restoring should succeed (auto-crumb preserves the current u.txt)
    run git crumb back 0
    [ "$status" -eq 0 ]
    [ "$(cat u.txt)" = "first-untracked" ]

    # The auto-crumb should hold the "CURRENT" version
    expected_sha=$(git rev-parse refs/worktree/crumb@{0})
    [ "$(git cat-file -p "${expected_sha}^3:u.txt")" = "CURRENT" ]
}

# --- T14 ---------------------------------------------------------------------
@test "reflog persists across many leaves (bootstrap is durable)" {
    for i in $(seq 1 20); do
        echo "$i" > a.txt
        git crumb leave -m "iter-$i" > /dev/null
    done

    run git crumb list
    [ "$(echo "$output" | wc -l)" -eq 20 ]

    # Verify reflog walk
    run git log -g --format=%gs refs/worktree/crumb
    [ "$(echo "$output" | wc -l)" -eq 20 ]
}

# --- T16 (trails) ------------------------------------------------------------
@test "--trail=<name> stores on refs/crumb.<name> only" {
    echo modified > a.txt
    run git crumb --trail experiment leave -m e1
    [ "$status" -eq 0 ]

    git rev-parse --verify refs/crumb.experiment
    run git rev-parse --verify refs/worktree/crumb
    [ "$status" -ne 0 ]
}

# --- T17 ---------------------------------------------------------------------
@test "default and named trails are independent" {
    echo m1 > a.txt; git crumb leave -m m1
    echo e1 > a.txt; git crumb --trail experiment leave -m e1

    run git crumb list
    [ "$(echo "$output" | wc -l)" -eq 1 ]
    [[ "$output" == *"crumb@{0}: m1"* ]]

    run git crumb --trail experiment list
    [ "$(echo "$output" | wc -l)" -eq 1 ]
    [[ "$output" == *"crumb.experiment@{0}: e1"* ]]
}

# --- T18 ---------------------------------------------------------------------
@test "default trail is per-worktree; named trail is shared across worktrees" {
    # leave on main worktree's default and on a named trail
    echo main-default > a.txt
    git crumb leave -m main-default
    echo main-shared > a.txt
    git crumb --trail shared leave -m main-shared

    # Add a linked worktree based on an existing commit
    git worktree add -q ../wt-b -b wt-b HEAD

    (
        cd ../wt-b

        # Default trail in the linked worktree is empty (per-worktree)
        run git crumb list
        [ "$status" -eq 0 ]
        [ -z "$output" ]

        # Named trail "shared" is visible from here
        run git crumb --trail shared list
        [ "$(echo "$output" | wc -l)" -eq 1 ]
        [[ "$output" == *"crumb.shared@{0}: main-shared"* ]]

        # Leave on the linked worktree's default trail
        echo wt-b-default > a.txt
        git crumb leave -m wt-b-default

        # Linked worktree sees its own default
        run git crumb list
        [ "$(echo "$output" | wc -l)" -eq 1 ]
        [[ "$output" == *"wt-b-default"* ]]
    )

    # Back in the main worktree, the default trail should still show main-default only
    run git crumb list
    [ "$(echo "$output" | wc -l)" -eq 1 ]
    [[ "$output" == *"main-default"* ]]

    # Cleanup
    git worktree remove -f ../wt-b
}

# --- T19 ---------------------------------------------------------------------
@test "--trail accepts both = and space form, before or after the subcommand" {
    echo m > a.txt
    git crumb --trail=t1 leave -m before-eq
    echo m2 > a.txt
    git crumb --trail t2 leave -m before-space
    echo m3 > a.txt
    git crumb leave --trail=t3 -m after-eq
    echo m4 > a.txt
    git crumb leave --trail t4 -m after-space

    git rev-parse --verify refs/crumb.t1
    git rev-parse --verify refs/crumb.t2
    git rev-parse --verify refs/crumb.t3
    git rev-parse --verify refs/crumb.t4
}

# --- T20 ---------------------------------------------------------------------
@test "invalid trail name is rejected" {
    echo m > a.txt
    run git crumb --trail '..' leave -m bad
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid trail name"* ]]

    run git crumb --trail 'with space' leave -m bad
    [ "$status" -ne 0 ]
}

# --- T21 ---------------------------------------------------------------------
@test "list label reflects the active trail" {
    echo m > a.txt
    git crumb leave -m default-one

    echo e > a.txt
    git crumb --trail feature leave -m feature-one

    run git crumb list
    [[ "$(echo "$output" | sed -n 1p)" == "crumb@{0}: default-one" ]]

    run git crumb --trail feature list
    [[ "$(echo "$output" | sed -n 1p)" == "crumb.feature@{0}: feature-one" ]]
}
