if [[ $OSTYPE == darwin* ]]; then
  [[ -r "$HOME/.orbstack/shell/init.zsh" ]] && source "$HOME/.orbstack/shell/init.zsh"
  [[ -d /Applications/Obsidian.app/Contents/MacOS ]] && \
    path+=(/Applications/Obsidian.app/Contents/MacOS)
fi

[[ -d "$HOME/.dotnet/tools" ]] && path+=("$HOME/.dotnet/tools")

# Login shells: re-assert mise first, because macOS path_helper reorders PATH
# after .zshenv has run.
[[ -d "$HOME/.local/share/mise/shims" ]] && path=("$HOME/.local/share/mise/shims" $path)
typeset -U path PATH
export PATH
