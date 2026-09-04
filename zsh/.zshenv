# Homebrew - must be first to set up PATH for other tools
eval "$(/opt/homebrew/bin/brew shellenv)"

# Cargo/Rust
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Core PATH additions (available in all contexts)
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# Read-only HiPhi automation access. The token itself stays in the macOS
# Keychain; this service account can see only the dedicated HiPhi Automation
# vault, never the Personal/Private vault.
if [[ -z ${OP_SERVICE_ACCOUNT_TOKEN:-} ]]; then
  hiphi_op_token=$(/usr/bin/security find-generic-password \
    -a muness1 \
    -s com.openhorizon.codex.1password-service-account \
    -w 2>/dev/null) || hiphi_op_token=
  if [[ -n $hiphi_op_token ]]; then
    export OP_SERVICE_ACCOUNT_TOKEN=$hiphi_op_token
  fi
  unset hiphi_op_token
fi
