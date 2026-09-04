# If you come from bash you might have to change your $PATH.
export PATH="$HOME/.cargo/bin:$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"

export FPATH=$HOME/.config/.zsh/functions:$FPATH

# Oh My Zsh (optional — skip if not installed)
export ZSH="$HOME/.oh-my-zsh"
if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  ZSH_THEME="agnoster-light"
  zstyle :omz:plugins:iterm2 shell-integration yes
  plugins=(git git-prompt ohmyzsh-full-autoupdate 1password dotenv direnv gh iterm2 vscode zsh-interactive-cd fzf)
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit && compinit -C 2>/dev/null
  [[ -z ${PROMPT+X}${RPROMPT+X} ]] && PROMPT='%n@%m %~ %# '
fi

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

if typeset -f __shhist_prompt >/dev/null 2>&1; then
  precmd_functions=(__shhist_prompt $precmd_functions)
fi

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init - zsh)"
  eval "$(pyenv virtualenv-init -)"
fi

[[ -f "$HOME/.acme.sh/acme.sh.env" ]] && . "$HOME/.acme.sh/acme.sh.env"
[[ -d /opt/homebrew/opt/openjdk/bin ]] && export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

alias get_idf='. $HOME/esp/esp-idf/export.sh'



# =============================================
# Shell enhancements (Starship, mise, fzf, zoxide, Atuin, …)
# =============================================

export BUN_INSTALL="$HOME/.bun"
[[ -d $BUN_INSTALL ]] && export PATH="$BUN_INSTALL/bin:$PATH"

command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"

[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

if [[ -d $HOME/.docker/completions ]]; then
  fpath=($HOME/.docker/completions $fpath)
  autoload -Uz compinit && compinit -i 2>/dev/null
fi

_autosug=/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
_highlight=/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
if [[ -f $_autosug ]]; then
  source "$_autosug"
  export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
  export ZSH_AUTOSUGGEST_USE_ASYNC=1
  export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6c7086"
  export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
fi
[[ -f $_highlight ]] && source "$_highlight"
unset _autosug _highlight

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
  export FZF_DEFAULT_OPTS="
  --height 40%
  --layout=reverse
  --border
  --preview-window=right:50%
  --bind='ctrl-/:toggle-preview'
"
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
fi

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh)"

# Atuin config location (when installed): ~/.config/atuin/config.toml

# ==============================================
# QUICK REFERENCE
# ==============================================
# Auto-suggestions: Type and see gray suggestions → Right arrow to accept
# Syntax highlighting: Valid commands = green, invalid = red
# fzf history: CTRL-R for fuzzy command history search
# fzf files: CTRL-T to find and insert files
# fzf dirs: ALT-C to cd into directory
# zoxide: Use 'z' instead of 'cd' (learns your patterns)
# Atuin: Enhanced CTRL-R with full-text search across all history
# ==============================================

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# Amp CLI
export PATH="$HOME/.amp/bin:$PATH"

# Claude Code configurations
alias claude-artium='CLAUDE_CONFIG_DIR=~/.claude-artium claude'

RUSTC_WRAPPER=sccache

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
