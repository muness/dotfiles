# Core user paths for every zsh invocation.
typeset -U path PATH
path=("$HOME/bin" "$HOME/.local/bin" "$HOME/.cargo/bin" $path)
export PATH

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Homebrew and macOS Keychain integration stay on macOS.
if [[ $OSTYPE == darwin* ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if [[ -z ${OP_SERVICE_ACCOUNT_TOKEN:-} && -x /usr/bin/security ]]; then
    hiphi_op_token=$(/usr/bin/security find-generic-password \
      -a muness1 \
      -s com.openhorizon.codex.1password-service-account \
      -w 2>/dev/null) || hiphi_op_token=
    if [[ -n $hiphi_op_token ]]; then
      export OP_SERVICE_ACCOUNT_TOKEN=$hiphi_op_token
    fi
    unset hiphi_op_token
  fi
fi

# Keep Cargo build output out of source trees, one directory per workspace.
# /Volumes/src is shared between macOS and Linux, and a target/ built on one
# OS is wrong on the other. A single global target dir would serialise
# concurrent builds (agents, worktrees) on Cargo's lock, so key it by the
# enclosing git root. Outside a git checkout Cargo uses ./target as usual.
_cargo_target_dir() {
  local dir=${PWD:A}
  while [[ $dir != / && ! -e $dir/.git ]]; do dir=${dir:h}; done
  if [[ -e $dir/.git ]]; then
    export CARGO_TARGET_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cargo-target/${${dir#/}//\//%}"
  else
    unset CARGO_TARGET_DIR
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _cargo_target_dir
_cargo_target_dir
