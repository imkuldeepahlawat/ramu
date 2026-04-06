#!/usr/bin/env bash
# install.sh — One-line installer for ramu
# Usage: curl -fsSL https://raw.githubusercontent.com/imkuldeepahlawat/ramu/main/install.sh | bash
#
# Compatible with: bash 3.2+, zsh

set -e

REPO="https://raw.githubusercontent.com/imkuldeepahlawat/ramu/main"
SCRIPTS_DIR="$HOME/scripts"
DB="$SCRIPTS_DIR/ramu.db"

# Detect shell config file
if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
  SHELLRC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELLRC="$HOME/.bashrc"
else
  SHELLRC="$HOME/.profile"
fi

echo ""
echo "  📦 ramu — one-line install"
echo "  ─────────────────────────────────────"

# 0. Check dependencies
missing=""
for cmd in sqlite3 curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing="$missing $cmd"
  fi
done
if [ -n "$missing" ]; then
  echo "  ❌ Missing dependencies:$missing"
  echo "     Install them first, then re-run."
  exit 1
fi

# 1. Create ~/scripts if needed
mkdir -p "$SCRIPTS_DIR"

# 2. Download ramu.sh
echo "  Downloading ramu.sh..."
curl -fsSL "$REPO/ramu.sh" -o "$SCRIPTS_DIR/ramu.sh"
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

# 4. Add alias to shell config (skip if already present)
if grep -q 'alias ramu=' "$SHELLRC" 2>/dev/null; then
  echo "  ⏭️  Alias already in $SHELLRC — skipped"
else
  printf '\n# ramu — Downloads organizer\nalias ramu="bash $HOME/scripts/ramu.sh"\n' >> "$SHELLRC"
  echo "  ✅ Alias added to $SHELLRC"
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
echo "     source $SHELLRC"
echo ""
echo "  Then run:  ramu help"
echo ""
echo "  🤖 AI features: ramu uses Ollama for AI. Choose one:"
echo "     Option A:  Install Ollama → https://ollama.com/download"
echo "     Option B:  Use Docker   → ramu ai-start"
echo ""
