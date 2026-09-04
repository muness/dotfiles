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
