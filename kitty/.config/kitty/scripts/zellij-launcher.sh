#!/bin/zsh
/opt/homebrew/bin/zellij attach --create 2>/tmp/zellij-error.log
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    echo "⚠️  Zellij failed to start (exit code: $exit_code)"
    [[ -s /tmp/zellij-error.log ]] && echo "Error: $(cat /tmp/zellij-error.log)"
    echo "Falling back to plain zsh...\n"
    exec /bin/zsh
fi
