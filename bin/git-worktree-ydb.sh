#!/usr/bin/env bash

_git_worktree_ydb_create() {
    local ydb_main="/home/eivanov89/repos/ydb_main"
    local worktree_root="/home/eivanov89/repos/ydb_worktrees"
    local name="${1-}"
    local revision="${2:-main}"
    local worktree_path

    if [[ $# -lt 1 || $# -gt 2 ]]; then
        printf 'Usage: %s name [commit|branch]\n' "${BASH_SOURCE[0]}" >&2
        return 2
    fi

    if [[ -z "$name" || "$name" == */* || "$name" == "." || "$name" == ".." ]]; then
        printf 'Error: name must be a single directory name\n' >&2
        return 2
    fi

    if [[ ! -d "$ydb_main/.git" && ! -f "$ydb_main/.git" ]]; then
        printf 'Error: YDB checkout not found at %s\n' "$ydb_main" >&2
        return 1
    fi

    if ! git -C "$ydb_main" check-ref-format --branch "$name" >/dev/null; then
        printf 'Error: invalid branch name: %s\n' "$name" >&2
        return 2
    fi

    worktree_path="$worktree_root/$name"
    if [[ -e "$worktree_path" || -L "$worktree_path" ]]; then
        printf 'Error: worktree path already exists: %s\n' "$worktree_path" >&2
        return 1
    fi

    if ! mkdir -p "$worktree_root"; then
        return 1
    fi

    if git -C "$ydb_main" show-ref --verify --quiet "refs/heads/$name"; then
        if ! git -C "$ydb_main" worktree add "$worktree_path" "$name"; then
            return 1
        fi
        printf 'Branch already exists; using it: %s\n' "$name"
    else
        if ! git -C "$ydb_main" worktree add -b "$name" "$worktree_path" "$revision"; then
            return 1
        fi
        printf 'Created branch %s from %s\n' "$name" "$revision"
    fi

    YDB_WORKTREE_YDB_PATH="$worktree_path"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if _git_worktree_ydb_create "$@"; then
        printf 'To enter it in your current shell, run: cd %q\n' "$YDB_WORKTREE_YDB_PATH"
    else
        exit $?
    fi
else
    if _git_worktree_ydb_create "$@"; then
        cd "$YDB_WORKTREE_YDB_PATH" || return 1
    else
        return $?
    fi
fi
