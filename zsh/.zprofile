if [[ $OSTYPE == darwin* ]]; then
  [[ -r "$HOME/.orbstack/shell/init.zsh" ]] && source "$HOME/.orbstack/shell/init.zsh"
  [[ -d /Applications/Obsidian.app/Contents/MacOS ]] && \
    path+=(/Applications/Obsidian.app/Contents/MacOS)
fi

[[ -d "$HOME/.dotnet/tools" ]] && path+=("$HOME/.dotnet/tools")
typeset -U path PATH
export PATH
