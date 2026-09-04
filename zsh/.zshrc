# Interactive shell configuration shared by Linux and macOS.
typeset -U path PATH fpath FPATH
[[ -d "$HOME/.config/.zsh/functions" ]] && fpath=("$HOME/.config/.zsh/functions" $fpath)

HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
HISTSIZE=50000
SAVEHIST=10000
setopt append_history extended_history hist_expire_dups_first hist_ignore_dups
setopt hist_ignore_space share_history interactive_comments

export EDITOR=${EDITOR:-vim}
export VISUAL=${VISUAL:-$EDITOR}
export PAGER=${PAGER:-less}

if [[ $OSTYPE == darwin* && -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then
  path=(/opt/homebrew/opt/coreutils/libexec/gnubin $path)
fi

# Oh My Zsh is optional. A fast built-in prompt and completion are the fallback.
export ZSH="$HOME/.oh-my-zsh"
if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  ZSH_THEME="agnoster-light"
  plugins=(git dotenv direnv gh fzf)
  if [[ $OSTYPE == darwin* ]]; then
    zstyle :omz:plugins:iterm2 shell-integration yes
    plugins+=(1password iterm2 vscode)
  fi
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit && compinit -C
  PROMPT='%F{green}%n@%m%f %F{blue}%~%f %# '
fi

command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh)"

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --preview-window=right:50% --bind=ctrl-/:toggle-preview"
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  elif command -v fdfind >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
  fi
  export FZF_CTRL_T_COMMAND=${FZF_DEFAULT_COMMAND:-}
fi

for _autosug in \
  /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  if [[ -r $_autosug ]]; then
    source "$_autosug"
    export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    export ZSH_AUTOSUGGEST_USE_ASYNC=1
    export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
    export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    break
  fi
done
unset _autosug

export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL/bin" ]] && path+=("$BUN_INSTALL/bin")
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

if [[ $OSTYPE == darwin* ]]; then
  export PNPM_HOME="$HOME/Library/pnpm"
else
  export PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
fi
[[ -d $PNPM_HOME ]] && path+=("$PNPM_HOME")

[[ -d "$HOME/.opencode/bin" ]] && path+=("$HOME/.opencode/bin")
[[ -d "$HOME/.amp/bin" ]] && path+=("$HOME/.amp/bin")
[[ -r "$HOME/google-cloud-sdk/path.zsh.inc" ]] && source "$HOME/google-cloud-sdk/path.zsh.inc"
[[ -r "$HOME/google-cloud-sdk/completion.zsh.inc" ]] && source "$HOME/google-cloud-sdk/completion.zsh.inc"
[[ -r "$HOME/esp/esp-idf/export.sh" ]] && alias get_idf='. "$HOME/esp/esp-idf/export.sh"'

command -v sccache >/dev/null 2>&1 && export RUSTC_WRAPPER=sccache

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  alias fd=fdfind
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  alias bat=batcat
fi

typeset -U path PATH
export PATH

# Syntax highlighting must be sourced after other interactive shell setup.
for _highlight in \
  /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  if [[ -r $_highlight ]]; then
    source "$_highlight"
    break
  fi
done
unset _highlight
