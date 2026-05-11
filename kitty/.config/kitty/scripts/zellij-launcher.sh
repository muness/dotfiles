#!/bin/sh
# Used for ⌘N / shell=. Never loads zshrc (Kitty used to run `zsh -il` → heavy rc → failures).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

for zellij_bin in /opt/homebrew/bin/zellij /usr/local/bin/zellij; do
  if [ -x "$zellij_bin" ]; then
    exec "$zellij_bin" attach --create default-session
  fi
done

if command -v zellij >/dev/null 2>&1; then
  exec zellij attach --create default-session
fi

echo "zellij not found; PATH=$PATH" >&2
exec /bin/zsh -il
