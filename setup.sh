#!/usr/bin/env bash
# setup.sh — Install ramu on your machine
# Compatible with: bash 3.2+, zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$HOME/scripts"
ZSHRC="$HOME/.zshrc"
DB="$SCRIPTS_DIR/ramu.db"

echo ""
echo "  📦 ramu setup"
echo "  ─────────────────────────────────────"

# 0. Check dependencies
for cmd in sqlite3 curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "  ❌ Missing dependency: $cmd"
    echo "     Install it before running setup."
    exit 1
  fi
done

# 1. Create ~/scripts if needed
mkdir -p "$SCRIPTS_DIR"

# 2. Copy ramu.sh
cp "$SCRIPT_DIR/ramu.sh" "$SCRIPTS_DIR/ramu.sh"
chmod +x "$SCRIPTS_DIR/ramu.sh"
echo "  ✅ Installed → $SCRIPTS_DIR/ramu.sh"

# 3. Init SQLite DB
sqlite3 "$DB" "
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS sessions (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT    NOT NULL,
  dir   TEXT    NOT NULL,
  moved INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS moves (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  src        TEXT NOT NULL,
  dst        TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS file_descriptions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  filepath    TEXT NOT NULL UNIQUE,
  filename    TEXT NOT NULL,
  folder      TEXT NOT NULL,
  description TEXT,
  ai_category TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);"
echo "  ✅ Database  → $DB"

# 4. Add alias to .zshrc (skip if already present)
if grep -q 'alias ramu=' "$ZSHRC" 2>/dev/null; then
  echo "  ⏭️  Alias already in $ZSHRC — skipped"
else
  echo '\n# ramu — Downloads organizer\nalias ramu="bash $HOME/scripts/ramu.sh"' >> "$ZSHRC"
  echo "  ✅ Alias added to $ZSHRC"
fi

# 5. Add cron job (daily 9am) if not already present
if crontab -l 2>/dev/null | grep -q "ramu.sh"; then
  echo "  ⏭️  Cron job already exists — skipped"
else
  (crontab -l 2>/dev/null; echo "0 9 * * * /bin/bash $HOME/scripts/ramu.sh >> $HOME/scripts/ramu.log 2>&1") | crontab -
  echo "  ✅ Cron job → daily at 9am"
fi

echo ""
echo "  🎉 Done! Reload your shell:"
echo "     source ~/.zshrc"
echo ""
echo "  Then run:  ramu help"
echo ""
echo "  🤖 AI features: ramu uses Ollama for AI. Choose one:"
echo "     Option A:  Install Ollama → https://ollama.com/download"
echo "     Option B:  Use Docker   → ramu ai-start"
echo ""
