# Homebrew - must be first to set up PATH for other tools
eval "$(/opt/homebrew/bin/brew shellenv)"

# Cargo/Rust
. "$HOME/.cargo/env"

# Core PATH additions (available in all contexts)
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
