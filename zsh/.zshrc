# If you come from bash you might have to change your $PATH.
export PATH="$HOME/.cargo/bin:$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

export FPATH=$HOME/.config/.zsh/functions:$FPATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

zstyle :omz:plugins:iterm2 shell-integration yes

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git git-prompt ohmyzsh-full-autoupdate asdf 1password dotenv direnv gh iterm2 vscode zsh-interactive-cd fzf)

ZSH_THEME=agnoster-light

source $ZSH/oh-my-zsh.sh

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

# integrating prompt function in prompt
precmd_functions=(__shhist_prompt $precmd_functions)
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"
eval "$(pyenv virtualenv-init -)"

. "$HOME/.acme.sh/acme.sh.env"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

eval "$(direnv hook zsh)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

alias get_idf='. $HOME/esp/esp-idf/export.sh'



# =============================================
# Added by ghostty-warp setup
# Sat Nov  8 15:34:30 EST 2025
# =============================================
#!/usr/bin/env bash

# ==============================================
# Complete Zsh Configuration
# ==============================================
# This file contains the COMPLETE zsh configuration
# that should be added to ~/.zshrc
#
# IMPORTANT: This is meant to be APPENDED, not replace
# your existing .zshrc (keeps Oh My Zsh config)

# ==============================================
# PATH Additions
# ==============================================

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# ==============================================
# Version Managers
# ==============================================

# mise (universal version manager)
eval "$(mise activate zsh)"

# fnm (Fast Node Manager)
eval "$(fnm env --use-on-cd)"

# ==============================================
# Bun Completions
# ==============================================

[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# ==============================================
# Prompt
# ==============================================

# Starship prompt
eval "$(starship init zsh)"

# ==============================================
# Docker Completions
# ==============================================

fpath=($HOME/.docker/completions $fpath)
autoload -Uz compinit
compinit

# ==============================================
# INTELLIGENT AUTOCOMPLETE & SHELL ENHANCEMENTS
# ==============================================

# --- zsh-autosuggestions Configuration ---
# Fish-like autosuggestions based on history
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# Optimization: Limit buffer size for better performance
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

# Enable async mode for faster suggestions
export ZSH_AUTOSUGGEST_USE_ASYNC=1

# Customize suggestion color (subtle gray)
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6c7086"

# Suggest from history and completion
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# --- zsh-syntax-highlighting Configuration ---
# Must be loaded AFTER zsh-autosuggestions
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# --- fzf Configuration ---
# Fuzzy finder for files, history, and more
source <(fzf --zsh)

# fzf key bindings:
# - CTRL-T: Paste selected files/dirs into command line
# - CTRL-R: Search command history (IMPROVED with fzf!)
# - ALT-C:  cd into selected directory

# Custom fzf options for better UX
export FZF_DEFAULT_OPTS="
  --height 40%
  --layout=reverse
  --border
  --preview-window=right:50%
  --bind='ctrl-/:toggle-preview'
"

# Use fd (if available) for better file finding
if command -v fd &> /dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# --- zoxide Configuration ---
# Smart directory navigation (replaces cd with learning capabilities)
eval "$(zoxide init zsh)"

# Usage:
# - z <keyword>    : Jump to a directory matching keyword
# - zi             : Interactive directory search (requires fzf)
# - z -            : Go back to previous directory

# --- Atuin Configuration ---
# Intelligent shell history with search and sync
eval "$(atuin init zsh)"

# Atuin key bindings:
# - CTRL-R: Search through ALL your command history with fuzzy search
# - UP:     Navigate through history with context awareness

# Atuin config location: ~/.config/atuin/config.toml

# ==============================================
# Ghostty Configuration Aliases
# ==============================================

alias gconfig="$HOME/.config/ghostty/gconfig"
alias ghostty-warp="$HOME/.config/ghostty/interactive-config.sh"
alias gconfig-interactive="$HOME/.config/ghostty/interactive-config.sh"
alias gconfig-switch="$HOME/.config/ghostty/switch-config.sh"

# Quick preset aliases
alias gcyber="$HOME/.config/ghostty/gconfig cyber"
alias gminimal="$HOME/.config/ghostty/gconfig minimal"
alias gcozy="$HOME/.config/ghostty/gconfig cozy"
alias gpro="$HOME/.config/ghostty/gconfig pro"

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
