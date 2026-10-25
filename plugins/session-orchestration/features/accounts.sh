# Feature accounts (features.accounts in .claude/coordination.local.json), sourced by lib.sh's list_accounts.
# Each CLAUDE_CONFIG_DIR is an account with its own background daemon and `claude agents` list; those whose projects/
# is the same directory share one transcript store, so all are asked. Prints "CONFIG_DIR<TAB>command prefix" per
# account: the current one first (plain `claude`), then ~/.claude and every ~/.claude-*.
list_accounts() {
  local d seen= cur=${CLAUDE_CONFIG_DIR:-$HOME/.claude} proj
  cur=${cur%/}
  proj=$(cd "$cur/projects" 2>/dev/null && pwd -P) || { printf '%s\tclaude\n' "$cur"; return; }
  for d in "$cur" "$HOME/.claude" "$HOME"/.claude-*; do
    case " $seen " in *" $d "*) continue ;; esac; seen="$seen $d"
    [ -d "$d" ] && [ "$(cd "$d/projects" 2>/dev/null && pwd -P)" = "$proj" ] || continue
    if [ "$d" = "$cur" ]; then printf '%s\tclaude\n' "$d"
    elif [ "$d" = "$HOME/.claude" ]; then printf '%s\tenv -u CLAUDE_CONFIG_DIR claude\n' "$d"
    else printf '%s\tCLAUDE_CONFIG_DIR=%s claude\n' "$d" "${d/#$HOME/~}"
    fi
  done
}
