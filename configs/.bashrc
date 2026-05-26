REPOS_DIR=`realpath ~/repos/`
CONFIGS_DIR=$REPOS_DIR/my-env/configs

CUSTOM_BIN_DIRS=(~/.local/bin ~/bin ~/.jenv/bin $REPOS_DIR/my-env/bin)
CONFIG_FILES=(~/.bashrc.local $CONFIGS_DIR/.bashrc.ydb ~/junk/my_configs/.bashrc.yandex ~/.cargo/env)

# Stable SSH agent socket path
SSH_AUTH_SOCK_LINK="$HOME/.ssh/ssh_auth_sock"

export TZ=Europe/Belgrade
export LC_ALL=en_US.UTF-8
export LANG=

export PROMPT_COMMAND=__prompt_command
function __prompt_command() {
    local EXIT="$?"             # This needs to be first

    #local RCol='\[\e[0m\]'
    local RCol='\[\033[00m\]'

    local Red='\[\e[0;31m\]'
    local Gre='\[\e[0;32m\]'
    local BYel='\[\e[1;33m\]'
    local BBlu='\[\033[36m\]'
    local Pur='\[\e[0;35m\]'

    local status=""
    if [ $EXIT != 0 ]; then
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

meminfo() {
    awk '/Hugepagesize:/{p=$2} / 0 /{next} / kB$/{v[sprintf("%9d GB %-s",int($2/1024/1024),$0)]=$2;next} {h[$0]=$2} \
/HugePages_Total/{hpt=$2} /HugePages_Free/{hpf=$2} {h["HugePages Used (Total-Free)"]=hpt-hpf} END{for(k in v) \
print sprintf("%-60s %10d",k,v[k]/p); for (k in h) print sprintf("%9d GB %-s",p*h[k]/1024/1024,k)}' /proc/meminfo\
|sort -nr|grep --color=auto -iE "^|( HugePage)[^:]*" #awk #meminfo
}

# iterm2
export ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX=YES

export PATH="$HOME/bin:$PATH"

export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTIGNORE='rm *:--revert*'
export HISTCONTROL=ignoredups

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

command -v ack-grep >/dev/null && alias ack='ack-grep'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF -1'
alias psu='ps -u $(whoami)'

alias r='vim -R -p'
alias v='vim -p'
alias vi='vim -p'

alias mkdt='date +%Y%m%d_%H%M'
alias mkts=mkdt

alias mylog='git log --author eivanov89'

ulimit -c unlimited
umask 022 # all to me, read to group and others

if [[ -n "$TMUX" ]]; then
    # Inside tmux: prefer the socket from tmux's current environment
    tmux_sock="$(tmux show-environment SSH_AUTH_SOCK 2>/dev/null | sed 's/^SSH_AUTH_SOCK=//')"

    if [[ -n "$tmux_sock" && -S "$tmux_sock" ]]; then
        ln -sfn "$tmux_sock" "$SSH_AUTH_SOCK_LINK"
    fi
else
    # Outside tmux: use the real SSH-forwarded socket from sshd
    if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" && ! -L "$SSH_AUTH_SOCK" ]]; then
        ln -sfn "$SSH_AUTH_SOCK" "$SSH_AUTH_SOCK_LINK"
    fi
fi

export SSH_AUTH_SOCK="$SSH_AUTH_SOCK_LINK"

for source_file in "${CONFIG_FILES[@]}"; do
    if [[ -e "$source_file" ]]; then
        source "$source_file"
    fi
done

for bin_path in "${CUSTOM_BIN_DIRS[@]}"; do
    if [[ -d "$bin_path" ]]; then
        export PATH="$bin_path:$PATH"
    fi
done
