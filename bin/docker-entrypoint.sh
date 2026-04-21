#!/bin/sh
# Docker entrypoint:
# 1. Fix volume permissions (created as root, need claude ownership)
# 2. Symlink .claude.json into persistent volume

CLAUDE_DIR="/home/claude/.claude"
CLAUDE_JSON="/home/claude/.claude.json"
CLAUDE_JSON_VOL="$CLAUDE_DIR/.claude.json"

# Fix ownership if volume was created as root
if [ -d "$CLAUDE_DIR" ]; then
  if [ "$(stat -c %U "$CLAUDE_DIR")" != "claude" ]; then
    echo "[entrypoint] Fixing volume permissions for $CLAUDE_DIR..."
    chown -R claude:claude "$CLAUDE_DIR"
  fi
fi

# Symlink .claude.json into volume so it persists across restarts
if [ -f "$CLAUDE_JSON_VOL" ] && [ ! -f "$CLAUDE_JSON" ]; then
  su-exec claude ln -sf "$CLAUDE_JSON_VOL" "$CLAUDE_JSON"
elif [ -f "$CLAUDE_JSON" ] && [ ! -L "$CLAUDE_JSON" ]; then
  cp "$CLAUDE_JSON" "$CLAUDE_JSON_VOL" 2>/dev/null
  chown claude:claude "$CLAUDE_JSON_VOL"
  rm -f "$CLAUDE_JSON"
  su-exec claude ln -sf "$CLAUDE_JSON_VOL" "$CLAUDE_JSON"
fi

exec su-exec claude "$@"
