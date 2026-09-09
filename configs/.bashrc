REPOS_DIR="$HOME/repos"
CONFIGS_DIR="$REPOS_DIR/my-env/configs"

CUSTOM_BIN_DIRS=("$HOME/.local/bin" "$HOME/bin" "$HOME/.jenv/bin" "$REPOS_DIR/my-env/bin")
CONFIG_FILES=("$HOME/.bashrc.local" "$CONFIGS_DIR/.bashrc.ydb" "$HOME/junk/my_configs/.bashrc.yandex" "$HOME/.cargo/env")

# Stable SSH agent socket path
SSH_AUTH_SOCK_LINK="$HOME/.ssh/ssh_auth_sock"

function __refresh_ssh_auth_sock() {
    local auth_sock="${SSH_AUTH_SOCK:-}"
    local tmux_env

    if [[ "$auth_sock" == "$SSH_AUTH_SOCK_LINK" && -S "$SSH_AUTH_SOCK_LINK" ]]; then
        return 0
    fi

    if [[ -n "$TMUX" ]]; then
        if tmux_env="$(tmux show-environment SSH_AUTH_SOCK 2>/dev/null)"; then
            if [[ "$tmux_env" == SSH_AUTH_SOCK=* ]]; then
                auth_sock="${tmux_env#SSH_AUTH_SOCK=}"
            fi
        fi
    fi

    # Do not replace the stable link with a link to itself.
    if [[ "$auth_sock" != "$SSH_AUTH_SOCK_LINK" && -S "$auth_sock" ]]; then
        ln -sfn "$auth_sock" "$SSH_AUTH_SOCK_LINK"
    fi

    if [[ -S "$SSH_AUTH_SOCK_LINK" ]]; then
        export SSH_AUTH_SOCK="$SSH_AUTH_SOCK_LINK"
    fi
}

export TZ=Europe/Belgrade
export LANG=en_US.UTF-8
unset LC_ALL

function __prompt_command() {
    local EXIT="$?"             # This needs to be first

    __refresh_ssh_auth_sock

    #local RCol='\[\e[0m\]'
    local RCol='\[\033[00m\]'

    local Red='\[\e[0;31m\]'
    local Gre='\[\e[0;32m\]'
    local BBlu='\[\033[36m\]'
    local Pur='\[\e[0;35m\]'

    local status=""
    if (( EXIT != 0 )); then
        status="${Red}\u${RCol}"      # Add red if exit code non 0
    else
        status="${Gre}\u${RCol}"
    fi

    if [[ -n "$SYS_VERSION" ]]
    then
        PS1="${Pur}\w\n$status${RCol}@${BBlu}\h${RCol}:$SYS_VERSION> "
    else
        PS1="${Pur}\w\n$status${RCol}@${BBlu}\h${RCol}> "
    fi
}

if [[ "${PROMPT_COMMAND:-}" != *"__prompt_command"* ]]; then
    PROMPT_COMMAND="__prompt_command${PROMPT_COMMAND:+$'\n'$PROMPT_COMMAND}"
fi

meminfo() {
    awk '/Hugepagesize:/{p=$2} / 0 /{next} / kB$/{v[sprintf("%9d GB %-s",int($2/1024/1024),$0)]=$2;next} {h[$0]=$2} \
/HugePages_Total/{hpt=$2} /HugePages_Free/{hpf=$2} {h["HugePages Used (Total-Free)"]=hpt-hpf} END{for(k in v) \
print sprintf("%-60s %10d",k,v[k]/p); for (k in h) print sprintf("%9d GB %-s",p*h[k]/1024/1024,k)}' /proc/meminfo\
|sort -nr|grep --color=auto -iE "^|( HugePage)[^:]*" #awk #meminfo
}

# iterm2
export ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX=YES

export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTIGNORE='rm *:--revert*'
export HISTCONTROL=ignoreboth

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

command -v ack-grep >/dev/null && alias ack='ack-grep'

function __print_entry_name() {
    local entry="$1"
    local name="${entry%/}"
    name="${name##*/}"

    printf '%s' "$name"
    if [[ -L "$entry" ]]; then
        printf ' -> %s' "$(readlink -- "$entry")"
    fi
    printf '\n'
}

function __list_entry_names() {
    local command_name="${FUNCNAME[1]}"
    local include_hidden="$1"
    local order_by_time="$2"
    shift 2

    local -a roots=("$@")
    ((${#roots[@]})) || roots=(.)

    local entry record root
    local show_headers=0
    local status=0
    ((${#roots[@]} > 1)) && show_headers=1

    for root in "${roots[@]}"; do
        if (( show_headers )); then
            printf '%s:\n' "$root"
        fi

        if [[ ! -e "$root" && ! -L "$root" ]]; then
            printf '%s: cannot access %q: No such file or directory\n' "$command_name" "$root" >&2
            status=1
        elif [[ ! -d "$root" ]]; then
            __print_entry_name "$root"
        elif (( order_by_time )); then
            while IFS= read -r -d '' record; do
                __print_entry_name "${record#* }"
            done < <(
                if (( include_hidden )); then
                    command find "$root" -mindepth 1 -maxdepth 1 -printf '%T@ %p\0'
                else
                    command find "$root" -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%T@ %p\0'
                fi | command sort -zn
            )
        else
            while IFS= read -r -d '' entry; do
                __print_entry_name "$entry"
            done < <(
                if (( include_hidden )); then
                    command find "$root" -mindepth 1 -maxdepth 1 -print0
                else
                    command find "$root" -mindepth 1 -maxdepth 1 ! -name '.*' -print0
                fi | command sort -z
            )
        fi

        if (( show_headers )); then
            printf '\n'
        fi
    done

    return "$status"
}

# Remove inherited aliases so they do not shadow these functions.
unalias l la 2>/dev/null

function l() {
    __list_entry_names 0 0 "$@"
}

function la() {
    __list_entry_names 1 0 "$@"
}

alias ll='ls -agolF'

function lt() {
    __list_entry_names 1 1 "$@"
}

alias psu='ps -u "$USER"'

alias r='vim -R -p'
alias v='vim -p'
alias vi='vim -p'

alias mkdt='date +%Y%m%d_%H%M'
alias mkts=mkdt

alias mylog='git log --author eivanov89'

ulimit -c unlimited
umask 022 # all to me, read to group and others

__refresh_ssh_auth_sock

for source_file in "${CONFIG_FILES[@]}"; do
    if [[ -r "$source_file" ]]; then
        source "$source_file"
    fi
done

function __path_prepend() {
    local bin_path="$1"

    if [[ -d "$bin_path" && ":$PATH:" != *":$bin_path:"* ]]; then
        PATH="$bin_path${PATH:+:$PATH}"
    fi
}

function __path_dedupe() {
    local entry deduped_path=""
    local first=1
    local -a path_entries
    local -A seen

    IFS=: read -r -a path_entries <<< "$PATH"
    for entry in "${path_entries[@]}"; do
        if [[ -n "${seen["entry:$entry"]+present}" ]]; then
            continue
        fi
        seen["entry:$entry"]=1

        if (( first )); then
            deduped_path="$entry"
            first=0
        else
            deduped_path+=":$entry"
        fi
    done

    PATH="$deduped_path"
}

for ((i = ${#CUSTOM_BIN_DIRS[@]} - 1; i >= 0; --i)); do
    __path_prepend "${CUSTOM_BIN_DIRS[i]}"
done
unset i
__path_dedupe
export PATH
