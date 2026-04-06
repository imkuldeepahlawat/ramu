#!/usr/bin/env bash
# ramu — Downloads organizer with SQLite undo (last 4 sessions)
# Compatible with: bash 3.2+, zsh, sh (any POSIX shell with process substitution)
#
# Usage:
#   ramu                  — run organizer
#   ramu help             — show full help
#   ramu history          — show last 4 sessions
#   ramu undo             — undo most recent session
#   ramu undo 2|3|4       — undo Nth most recent session

DOWNLOADS="${RAMU_DIR:-$HOME/Downloads}"
DB="$HOME/scripts/ramu.db"
SESSION_ID=""
moved=0

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Lowercase a string — POSIX compatible
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Extract file extension (after last dot), lowercased
file_ext() { lower "${1##*.}"; }

# Escape single quotes for SQLite
sql_esc() { printf '%s' "$1" | sed "s/'/''/g"; }

# ─────────────────────────────────────────────────────────────────────────────
# AI / Ollama helpers
# ─────────────────────────────────────────────────────────────────────────────
OLLAMA_URL="${RAMU_OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${RAMU_OLLAMA_MODEL:-mistral:latest}"
OLLAMA_TIMEOUT=60

# Check if Ollama is reachable (cached per invocation)
_ollama_ok=""
ollama_check() {
  if [ -z "$_ollama_ok" ]; then
    if curl -s --max-time 2 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
      _ollama_ok="yes"
    else
      _ollama_ok="no"
    fi
  fi
  [ "$_ollama_ok" = "yes" ]
}

# Send a prompt to Ollama, return the text response
# Usage: result=$(ollama_ask "your prompt here")
ollama_ask() {
  local prompt="$1"
  local payload
  payload=$(jq -n --arg model "$OLLAMA_MODEL" --arg prompt "$prompt" \
    '{model: $model, prompt: $prompt, stream: false}')

  local response
  response=$(curl -s --max-time "$OLLAMA_TIMEOUT" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$OLLAMA_URL/api/generate" 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$response" ]; then
    return 1
  fi

  printf '%s' "$response" | jq -r '.response // empty'
}

# Validate AI-generated WHERE clause (reject dangerous SQL)
validate_where() {
  local clause="$1"
  if printf '%s' "$clause" | grep -iEq '(DROP|DELETE|INSERT|UPDATE|ALTER|CREATE|ATTACH|DETACH|;|--)'; then
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# DB — init schema
# ─────────────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────────────
# Recorded move — logs src/dst to SQLite (needs SESSION_ID and moved vars set)
# ─────────────────────────────────────────────────────────────────────────────
rec_mv() {
  local src="$1" dst_dir="$2"
  local dst="$dst_dir/$(basename "$src")"
  mv "$src" "$dst_dir/" && {
    sqlite3 "$DB" "INSERT INTO moves (session_id,src,dst) VALUES ($SESSION_ID,'$(sql_esc "$src")','$(sql_esc "$dst")');"
    moved=$((moved + 1))
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Subcommand dispatch
# ─────────────────────────────────────────────────────────────────────────────
case "$1" in

  help|--help|-h)
    echo ""
    echo "  🗂️  ramu — Downloads organizer"
    echo "  ════════════════════════════════════════════════════"
    echo ""
    echo "  USAGE"
    echo "    ramu                 Organize ~/Downloads into typed subfolders"
    echo "    ramu help            Show this help message"
    echo "    ramu history         Show last 4 sessions (id · time · files moved)"
    echo "    ramu undo            Undo the most recent session"
    echo "    ramu undo 2          Undo the 2nd most recent session"
    echo "    ramu undo 3|4        Undo the 3rd or 4th most recent session"
    echo ""
    echo "  HOW IT WORKS"
    echo "    Pass 1 — moves files by extension into 38 main folders"
    echo "    Pass 2 — sub-sorts large folders (PDFs, Images, Videos, etc.)"
    echo "    Every move is recorded in SQLite (~/scripts/ramu.db)"
    echo "    Runs automatically every day at 9am via cron"
    echo ""
    echo "  MAIN FOLDERS"
    echo "    01 PDFs              02 Word Documents    03 Spreadsheets"
    echo "    04 Presentations     05 Notes & Text      06 eBooks & Comics"
    echo "    07 Images            08 RAW Photos        09 Videos"
    echo "    10 Audio             11 Subtitles         12 Playlists"
    echo "    13 Design Files      14 Adobe Files       15 3D Models & CAD"
    echo "    16 Web               17 Backend & Systems 18 Scripts & Shell"
    echo "    19 Config & Infra    20 Queries & Markup  21 Archives"
    echo "    22 Disk Images       23 Installers        24 Data & Databases"
    echo "    25 ML & AI Models    26 Scientific        27 Medical Imaging"
    echo "    28 Certificates      29 Email & Calendar  30 Fonts"
    echo "    31 Executables       32 Virtual Machines  33 Game & ROM Files"
    echo "    34 Backup & Temp     35 Torrent & P2P     36 Shortcuts"
    echo "    37 Patch & Diff      38 Logs              39 Other"
    echo ""
    echo "  SUB-FOLDERS (auto-created for large categories)"
    echo "    01 PDFs        →  Statements · Receipts · Agreements · Books"
    echo "                      Resumes · Tickets · Reports · Certificates"
    echo "    07 Images      →  PNG · JPEG · Vectors · Web · Animated · Apple · Icons"
    echo "    09 Videos      →  Screen Recordings · MOV · MP4 · MKV · WebM"
    echo "    10 Audio       →  MP3 · WAV · AAC · FLAC"
    echo "    15 3D Models   →  CAD & Architecture · 3D Models · Print Files · Blender"
    echo "    19 Config      →  Docker · Kubernetes · Secrets · Data Files"
    echo "    21 Archives    →  WhatsApp · iOS & Mobile · Google Drive · Projects"
    echo ""
    echo "  UNDO BEHAVIOUR"
    echo "    Each undo is isolated — only that session's files return to Downloads."
    echo "    Other sessions are unaffected. Up to 4 sessions are kept."
    echo ""
    echo "  SHELLS SUPPORTED"
    echo "    bash 3.2+, zsh, sh, fish (via bash)"
    echo ""
    echo "  AI COMMANDS (requires Ollama — local, Docker, or remote)"
    echo "    ramu ai-sort            Suggest better folders for '39 Other' files"
    echo "    ramu ai-sort --apply    Apply the AI suggestions"
    echo "    ramu ask \"query\"        Search files using natural language"
    echo "    ramu describe           Generate AI descriptions for organized files"
    echo "    ramu describe \"07 Images\"  Describe files in a specific folder"
    echo "    ramu ai-start           Start Ollama via Docker (if not running locally)"
    echo "    ramu ai-stop            Stop the ramu-ollama Docker container"
    echo ""
    echo "  ENVIRONMENT"
    echo "    RAMU_DIR=<path>              Override target directory (default: ~/Downloads)"
    echo "    RAMU_OLLAMA_URL=<url>        Override Ollama URL (default: http://localhost:11434)"
    echo "    RAMU_OLLAMA_MODEL=<model>    Override model (default: mistral:latest)"
    echo ""
    exit 0
    ;;

  history)
    echo ""
    echo "  ramu — last 4 sessions"
    echo "  ────────────────────────────────────────────────"
    sqlite3 -separator "|" "$DB" "
      SELECT
        '#' || s.id,
        s.ts,
        COUNT(m.id) || ' files',
        s.dir
      FROM sessions s
      LEFT JOIN moves m ON m.session_id = s.id
      GROUP BY s.id
      ORDER BY s.id DESC
      LIMIT 4;" | while IFS='|' read -r id ts files dir; do
        printf "  %-6s  %-22s  %-12s  %s\n" "$id" "$ts" "$files" "$dir"
      done
    echo ""
    exit 0
    ;;

  undo)
    N="${2:-1}"
    SESSION_ID=$(sqlite3 "$DB" \
      "SELECT id FROM sessions ORDER BY id DESC LIMIT 1 OFFSET $((N-1));")

    if [ -z "$SESSION_ID" ]; then
      echo "❌ No session at position $N  (run 'ramu history' to see available sessions)"
      exit 1
    fi

    TS=$(sqlite3 "$DB" "SELECT ts FROM sessions WHERE id=$SESSION_ID;")
    COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM moves WHERE session_id=$SESSION_ID;")
    echo ""
    echo "  ↩️  Undoing session #$SESSION_ID  ($TS)  —  $COUNT files"
    echo "  ────────────────────────────────────────────────"

    undone=0; missing=0
    while IFS='|' read -r src dst; do
      if [ -e "$dst" ]; then
        mkdir -p "$(dirname "$src")"
        mv "$dst" "$src" && undone=$((undone + 1))
      else
        echo "  ⚠️  missing: $(basename "$dst")  (skipped)"
        missing=$((missing + 1))
      fi
    done < <(sqlite3 "$DB" \
      "SELECT src, dst FROM moves WHERE session_id=$SESSION_ID ORDER BY id DESC;")

    # Clean up empty ramu-created dirs
    find "$DOWNLOADS" -mindepth 1 -maxdepth 2 -type d -empty -delete 2>/dev/null

    # Remove session (cascades to moves)
    sqlite3 "$DB" "PRAGMA foreign_keys=ON; DELETE FROM sessions WHERE id=$SESSION_ID;"

    echo ""
    echo "  ✅ Restored $undone files  |  ⚠️  $missing not found"
    echo ""
    exit 0
    ;;

  # ── AI: Docker-based Ollama management ───────────────────────────────────────
  ai-start)
    CONTAINER_NAME="ramu-ollama"

    # Check if Ollama is already reachable (local or existing container)
    if ollama_check; then
      echo ""
      echo "  ✅ Ollama is already running at $OLLAMA_URL"
      echo ""
      exit 0
    fi

    # Check for Docker
    if ! command -v docker >/dev/null 2>&1; then
      echo ""
      echo "  ❌ Docker not found. Install Docker or Ollama:"
      echo "     Docker:  https://docs.docker.com/get-docker/"
      echo "     Ollama:  https://ollama.com/download"
      echo ""
      exit 1
    fi

    # Check if container already exists but is stopped
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      echo "  Starting existing $CONTAINER_NAME container..."
      docker start "$CONTAINER_NAME" >/dev/null 2>&1
    else
      echo "  Creating $CONTAINER_NAME container..."
      docker run -d \
        --name "$CONTAINER_NAME" \
        -p 11434:11434 \
        -v ramu-ollama-data:/root/.ollama \
        ollama/ollama >/dev/null 2>&1
    fi

    # Wait for Ollama to become ready
    echo "  Waiting for Ollama to start..."
    attempts=0
    while [ "$attempts" -lt 30 ]; do
      if curl -s --max-time 2 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
        break
      fi
      sleep 1
      attempts=$((attempts + 1))
    done

    if ! curl -s --max-time 2 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
      echo "  ❌ Ollama container failed to start"
      exit 1
    fi

    # Check if model is available, pull if not
    model_exists=$(curl -s "$OLLAMA_URL/api/tags" 2>/dev/null | jq -r ".models[]?.name" 2>/dev/null | grep -c "$OLLAMA_MODEL")
    if [ "$model_exists" -eq 0 ]; then
      echo "  Pulling $OLLAMA_MODEL (this may take a few minutes on first run)..."
      docker exec "$CONTAINER_NAME" ollama pull "$OLLAMA_MODEL"
    fi

    echo ""
    echo "  ✅ Ollama is ready (Docker: $CONTAINER_NAME)"
    echo "     Model: $OLLAMA_MODEL"
    echo "     URL:   $OLLAMA_URL"
    echo ""
    exit 0
    ;;

  ai-stop)
    CONTAINER_NAME="ramu-ollama"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
      docker stop "$CONTAINER_NAME" >/dev/null 2>&1
      echo ""
      echo "  ✅ Stopped $CONTAINER_NAME container"
      echo "     Data is preserved — run 'ramu ai-start' to restart"
      echo ""
    else
      echo ""
      echo "  No running $CONTAINER_NAME container found."
      echo ""
    fi
    exit 0
    ;;

  # ── AI: smart re-categorize "39 Other" ──────────────────────────────────────
  ai-sort)
    if ! ollama_check; then
      echo ""
      echo "  ❌ Ollama is not running at $OLLAMA_URL"
      echo "     Start it with: ollama serve"
      echo ""
      exit 1
    fi

    apply=false; limit=20
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --apply) apply=true ;;
        --limit) shift; limit="$1" ;;
      esac
      shift
    done

    CATEGORIES="01 PDFs, 02 Word Documents, 03 Spreadsheets, 04 Presentations, 05 Notes & Text, 06 eBooks & Comics, 07 Images, 08 RAW Photos, 09 Videos, 10 Audio, 11 Subtitles, 12 Playlists, 13 Design Files, 14 Adobe Files, 15 3D Models & CAD, 16 Web, 17 Backend & Systems, 18 Scripts & Shell, 19 Config & Infra, 20 Queries & Markup, 21 Archives, 22 Disk Images, 23 Installers, 24 Data & Databases, 25 ML & AI Models, 26 Scientific, 27 Medical Imaging, 28 Certificates & Keys, 29 Email & Calendar, 30 Fonts, 31 Executables, 32 Virtual Machines, 33 Game & ROM Files, 34 Backup & Temp, 35 Torrent & P2P, 36 Shortcuts & Links, 37 Patch & Diff, 38 Logs"

    OTHER_DIR="$DOWNLOADS/39 Other"
    if [ ! -d "$OTHER_DIR" ]; then
      echo "  No '39 Other' folder found — nothing to sort."
      exit 0
    fi

    echo ""
    echo "  🤖 ramu ai-sort — analyzing files in 39 Other"
    echo "  ────────────────────────────────────────────────"

    if $apply; then
      SESSION_ID=$(sqlite3 "$DB" \
        "INSERT INTO sessions (ts, dir) VALUES ('$(date "+%Y-%m-%d %H:%M:%S")', '$(sql_esc "$DOWNLOADS")');
         SELECT last_insert_rowid();")
      moved=0
    fi

    # Build a quick extension->folder lookup for pre-AI matching
    # This catches files whose extension IS known but ended up in 39 Other
    # (e.g. files in subdirectories of 39 Other)
    _ext_lookup=""
    _ext_lookup="$_ext_lookup|pdf=01 PDFs|doc=02 Word Documents|docx=02 Word Documents|odt=02 Word Documents|rtf=02 Word Documents"
    _ext_lookup="$_ext_lookup|xls=03 Spreadsheets|xlsx=03 Spreadsheets|csv=03 Spreadsheets|numbers=03 Spreadsheets"
    _ext_lookup="$_ext_lookup|ppt=04 Presentations|pptx=04 Presentations|key=04 Presentations"
    _ext_lookup="$_ext_lookup|txt=05 Notes & Text|md=05 Notes & Text"
    _ext_lookup="$_ext_lookup|epub=06 eBooks & Comics|mobi=06 eBooks & Comics"
    _ext_lookup="$_ext_lookup|png=07 Images|jpg=07 Images|jpeg=07 Images|gif=07 Images|svg=07 Images|webp=07 Images|heic=07 Images|bmp=07 Images|tiff=07 Images|ico=07 Images|avif=07 Images"
    _ext_lookup="$_ext_lookup|raw=08 RAW Photos|cr2=08 RAW Photos|nef=08 RAW Photos|arw=08 RAW Photos|dng=08 RAW Photos"
    _ext_lookup="$_ext_lookup|mp4=09 Videos|mov=09 Videos|avi=09 Videos|mkv=09 Videos|wmv=09 Videos|flv=09 Videos|webm=09 Videos"
    _ext_lookup="$_ext_lookup|mp3=10 Audio|wav=10 Audio|aac=10 Audio|m4a=10 Audio|flac=10 Audio|ogg=10 Audio"
    _ext_lookup="$_ext_lookup|srt=11 Subtitles|ass=11 Subtitles|vtt=11 Subtitles"
    _ext_lookup="$_ext_lookup|fig=13 Design Files|sketch=13 Design Files|xd=13 Design Files"
    _ext_lookup="$_ext_lookup|psd=14 Adobe Files|ai=14 Adobe Files|indd=14 Adobe Files|aep=14 Adobe Files|prproj=14 Adobe Files"
    _ext_lookup="$_ext_lookup|dwg=15 3D Models & CAD|dxf=15 3D Models & CAD|stl=15 3D Models & CAD|blend=15 3D Models & CAD|obj=15 3D Models & CAD|fbx=15 3D Models & CAD|ifc=15 3D Models & CAD|step=15 3D Models & CAD|stp=15 3D Models & CAD|gltf=15 3D Models & CAD|glb=15 3D Models & CAD|skp=15 3D Models & CAD|rvt=15 3D Models & CAD|ply=15 3D Models & CAD"
    _ext_lookup="$_ext_lookup|html=16 Web|css=16 Web|js=16 Web|ts=16 Web|jsx=16 Web|tsx=16 Web|vue=16 Web|svelte=16 Web"
    _ext_lookup="$_ext_lookup|py=17 Backend & Systems|go=17 Backend & Systems|rs=17 Backend & Systems|java=17 Backend & Systems|c=17 Backend & Systems|cpp=17 Backend & Systems|swift=17 Backend & Systems|rb=17 Backend & Systems|php=17 Backend & Systems"
    _ext_lookup="$_ext_lookup|sh=18 Scripts & Shell|bash=18 Scripts & Shell|zsh=18 Scripts & Shell|ps1=18 Scripts & Shell|bat=18 Scripts & Shell"
    _ext_lookup="$_ext_lookup|json=19 Config & Infra|yaml=19 Config & Infra|yml=19 Config & Infra|toml=19 Config & Infra|xml=19 Config & Infra|ini=19 Config & Infra|cfg=19 Config & Infra|env=19 Config & Infra"
    _ext_lookup="$_ext_lookup|sql=20 Queries & Markup|graphql=20 Queries & Markup|tex=20 Queries & Markup"
    _ext_lookup="$_ext_lookup|zip=21 Archives|tar=21 Archives|gz=21 Archives|7z=21 Archives|rar=21 Archives|bz2=21 Archives"
    _ext_lookup="$_ext_lookup|iso=22 Disk Images|img=22 Disk Images|vmdk=22 Disk Images"
    _ext_lookup="$_ext_lookup|dmg=23 Installers|pkg=23 Installers|exe=23 Installers|msi=23 Installers|deb=23 Installers|rpm=23 Installers|apk=23 Installers"
    _ext_lookup="$_ext_lookup|db=24 Data & Databases|sqlite=24 Data & Databases|parquet=24 Data & Databases|geojson=24 Data & Databases"
    _ext_lookup="$_ext_lookup|ipynb=25 ML & AI Models|pkl=25 ML & AI Models|onnx=25 ML & AI Models|safetensors=25 ML & AI Models|gguf=25 ML & AI Models|pt=25 ML & AI Models"
    _ext_lookup="$_ext_lookup|mat=26 Scientific|nc=26 Scientific|fits=26 Scientific"
    _ext_lookup="$_ext_lookup|dcm=27 Medical Imaging|nii=27 Medical Imaging"
    _ext_lookup="$_ext_lookup|pem=28 Certificates & Keys|crt=28 Certificates & Keys|key=28 Certificates & Keys|pfx=28 Certificates & Keys|gpg=28 Certificates & Keys"
    _ext_lookup="$_ext_lookup|eml=29 Email & Calendar|msg=29 Email & Calendar|ics=29 Email & Calendar"
    _ext_lookup="$_ext_lookup|ttf=30 Fonts|otf=30 Fonts|woff=30 Fonts|woff2=30 Fonts"
    _ext_lookup="$_ext_lookup|so=31 Executables|dll=31 Executables|dylib=31 Executables"
    _ext_lookup="$_ext_lookup|ova=32 Virtual Machines|vmx=32 Virtual Machines"
    _ext_lookup="$_ext_lookup|rom=33 Game & ROM Files|nes=33 Game & ROM Files|gba=33 Game & ROM Files"
    _ext_lookup="$_ext_lookup|bak=34 Backup & Temp|backup=34 Backup & Temp|old=34 Backup & Temp|tmp=34 Backup & Temp|swp=34 Backup & Temp"
    _ext_lookup="$_ext_lookup|torrent=35 Torrent & P2P|part=35 Torrent & P2P|crdownload=35 Torrent & P2P"
    _ext_lookup="$_ext_lookup|url=36 Shortcuts & Links|webloc=36 Shortcuts & Links|lnk=36 Shortcuts & Links"
    _ext_lookup="$_ext_lookup|patch=37 Patch & Diff|diff=37 Patch & Diff"
    _ext_lookup="$_ext_lookup|log=38 Logs|err=38 Logs|crash=38 Logs|dump=38 Logs|trace=38 Logs"

    count=0; suggested=0
    while IFS= read -r -d '' f; do
      [ "$count" -ge "$limit" ] && break

      fname=$(basename "$f")

      # Skip hidden/system files
      case "$fname" in
        .*|Thumbs.db|desktop.ini) continue ;;
      esac

      count=$((count + 1))

      # Pre-AI check: if the extension is known, use rule-based lookup (no AI needed)
      ext=$(file_ext "$fname")
      rule_match=$(printf '%s' "$_ext_lookup" | tr '|' '\n' | grep "^${ext}=" | head -1 | cut -d'=' -f2-)
      if [ -n "$rule_match" ]; then
        suggested=$((suggested + 1))
        if $apply; then
          mkdir -p "$DOWNLOADS/$rule_match"
          rec_mv "$f" "$DOWNLOADS/$rule_match"
          printf "  ✅ %-40s → %s  (by extension)\n" "$fname" "$rule_match"
        else
          printf "  %-40s → %s  (by extension)\n" "$fname" "$rule_match"
        fi
        sqlite3 "$DB" "INSERT OR REPLACE INTO file_descriptions (filepath, filename, folder, ai_category)
          VALUES ('$(sql_esc "$DOWNLOADS/$rule_match/$fname")', '$(sql_esc "$fname")', '$(sql_esc "$rule_match")', '$(sql_esc "$rule_match")');"
        continue
      fi

      # Build prompt — add content preview for text files
      preview=""
      case "$(lower "$fname")" in
        *.txt|*.md|*.csv|*.json|*.xml|*.yaml|*.yml|*.log|*.cfg|*.ini|*.conf)
          preview=$(head -c 500 "$f" 2>/dev/null)
          ;;
      esac

      prompt="You are a strict file categorizer. You MUST respond with ONLY a folder name from the list below. No explanations, no alternatives, no parentheses, no extra text. Just the folder name.

FOLDERS AND THEIR FILE EXTENSIONS:
01 PDFs = .pdf
02 Word Documents = .doc .docx .odt .rtf .wpd .wps
03 Spreadsheets = .xls .xlsx .ods .csv .tsv .numbers .xlsm
04 Presentations = .ppt .pptx .odp .key .pps .ppsx
05 Notes & Text = .txt .md .markdown .rst .org .nfo .readme
06 eBooks & Comics = .epub .mobi .azw .fb2 .djvu .cbr .cbz
07 Images = .png .jpg .jpeg .heic .webp .gif .svg .bmp .tiff .ico .avif
08 RAW Photos = .raw .cr2 .cr3 .nef .arw .dng .orf .rw2
09 Videos = .mp4 .mov .avi .mkv .wmv .flv .webm .3gp .mpg .mpeg
10 Audio = .mp3 .wav .aac .m4a .flac .ogg .opus .wma .aiff
11 Subtitles = .srt .ass .ssa .vtt .sub
12 Playlists = .m3u .m3u8 .pls .xspf
13 Design Files = .fig .figma .sketch .xd .afdesign .procreate .kra
14 Adobe Files = .psd .psb .ai .indd .aep .prproj .fla
15 3D Models & CAD = .dwg .dxf .ifc .stl .ply .blend .step .stp .iges .obj .fbx .gltf .glb .dae .skp .rvt .3ds .usd .usdz .wrl .sat
16 Web = .html .htm .css .scss .sass .js .jsx .ts .tsx .vue .svelte
17 Backend & Systems = .py .rb .php .java .go .rs .c .cpp .h .cs .swift .kt .scala .dart .zig .lua
18 Scripts & Shell = .sh .bash .zsh .ps1 .bat .cmd .make .cmake
19 Config & Infra = .json .toml .yaml .yml .xml .plist .ini .cfg .conf .env .dockerfile .tf .hcl
20 Queries & Markup = .sql .graphql .proto .tex .latex .bib
21 Archives = .zip .tar .gz .bz2 .xz .7z .rar .cab
22 Disk Images = .iso .img .vmdk .vhd .qcow2
23 Installers = .dmg .pkg .exe .msi .deb .rpm .appimage .apk .ipa
24 Data & Databases = .db .sqlite .mdb .parquet .feather .arrow .geojson .kml .gpx .shp
25 ML & AI Models = .ipynb .pkl .pickle .pt .pth .onnx .h5 .safetensors .gguf .ggml .tflite
26 Scientific = .mat .nc .netcdf .fits .hdf4 .sav .dta
27 Medical Imaging = .dcm .dicom .nii .mgh
28 Certificates & Keys = .pem .cer .crt .csr .key .pfx .p12 .gpg .asc
29 Email & Calendar = .eml .msg .mbox .pst .ics
30 Fonts = .ttf .otf .woff .woff2 .eot
31 Executables = .out .so .dylib .dll .lib .elf
32 Virtual Machines = .ova .ovf .vmx .vbox
33 Game & ROM Files = .rom .nes .smc .gb .gba .nds .wad .n64
34 Backup & Temp = .bak .backup .old .orig .temp .tmp .swp
35 Torrent & P2P = .torrent .part .crdownload .aria2
36 Shortcuts & Links = .url .webloc .lnk .desktop
37 Patch & Diff = .patch .diff .rej
38 Logs = .log .logs .err .crash .dump .trace

RULES:
1. Match the file extension FIRST. If the extension is listed above, use that folder. This is the highest priority.
2. If the extension is not listed, use the filename and content to guess the best category.
3. Hidden files (starting with .) and system files (.DS_Store, .localized, Thumbs.db) = 39 Other.
4. If genuinely unsure, respond 39 Other.
5. RESPOND WITH ONLY THE FOLDER NAME. Example: 15 3D Models & CAD"

      if [ -n "$preview" ]; then
        prompt="$prompt

Filename: $fname
First 500 bytes of content:
$preview"
      else
        prompt="$prompt

Filename: $fname"
      fi

      suggestion=$(ollama_ask "$prompt")
      if [ $? -ne 0 ] || [ -z "$suggestion" ]; then
        printf "  ⚠️  %-40s  (AI request failed — skipped)\n" "$fname"
        continue
      fi

      # Clean whitespace and validate
      suggestion=$(printf '%s' "$suggestion" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # Resolve suggestion to a valid folder name
      resolved=""

      # 1. Try exact match against known categories (including "39 Other")
      if printf '%s' "$CATEGORIES, 39 Other" | grep -qF "$suggestion"; then
        resolved="$suggestion"
      else
        # 2. AI may return just a number (e.g. "15") — match by prefix
        #    Or wrong number prefix (e.g. "34 PDFs") — match by name part
        num_part=$(printf '%s' "$suggestion" | sed 's/[^0-9].*//') # leading digits only
        name_part=$(printf '%s' "$suggestion" | sed 's/^[0-9]*[[:space:]]*//')

        # 2a. Number-only response — find folder starting with that number
        if [ -n "$num_part" ] && [ -z "$name_part" ]; then
          IFS=','
          for cat_entry in $CATEGORIES; do
            cat_entry=$(printf '%s' "$cat_entry" | sed 's/^[[:space:]]*//')
            case "$cat_entry" in
              ${num_part}\ *) resolved="$cat_entry"; break ;;
            esac
          done
          unset IFS
        fi

        # 2b. Has a name part — try matching by name (ignoring number prefix)
        if [ -z "$resolved" ] && [ -n "$name_part" ]; then
          name_part_lower=$(lower "$name_part")
          IFS=','
          for cat_entry in $CATEGORIES; do
            cat_entry=$(printf '%s' "$cat_entry" | sed 's/^[[:space:]]*//')
            cat_name=$(printf '%s' "$cat_entry" | sed 's/^[0-9]*[[:space:]]*//')
            if [ "$(lower "$cat_name")" = "$name_part_lower" ]; then
              resolved="$cat_entry"
              break
            fi
          done
          unset IFS
        fi
      fi

      if [ -n "$resolved" ]; then
        if [ "$resolved" != "39 Other" ]; then
          suggested=$((suggested + 1))
          if $apply; then
            mkdir -p "$DOWNLOADS/$resolved"
            rec_mv "$f" "$DOWNLOADS/$resolved"
            printf "  ✅ %-40s → %s\n" "$fname" "$resolved"
          else
            printf "  %-40s → %s\n" "$fname" "$resolved"
          fi
          # Cache in file_descriptions
          sqlite3 "$DB" "INSERT OR REPLACE INTO file_descriptions (filepath, filename, folder, ai_category)
            VALUES ('$(sql_esc "$DOWNLOADS/$resolved/$fname")', '$(sql_esc "$fname")', '$(sql_esc "$resolved")', '$(sql_esc "$resolved")');"
        else
          printf "  %-40s   (AI says keep in 39 Other)\n" "$fname"
        fi
      else
        printf "  ⚠️  %-40s  (invalid suggestion: %s)\n" "$fname" "$suggestion"
      fi
    done < <(find "$OTHER_DIR" -type f -print0)

    echo ""
    if $apply; then
      sqlite3 "$DB" "UPDATE sessions SET moved=$moved WHERE id=$SESSION_ID;"
      echo "  ✅ Moved $suggested files  (session #$SESSION_ID)"
      echo "     Run 'ramu undo' to reverse"
    else
      echo "  $suggested suggestions  (run 'ramu ai-sort --apply' to execute)"
    fi
    echo ""
    exit 0
    ;;

  # ── AI: natural language search ─────────────────────────────────────────────
  ask)
    shift
    query="$*"
    if [ -z "$query" ]; then
      echo ""
      echo "  Usage: ramu ask \"your question\""
      echo "  Example: ramu ask \"where did my resume go\""
      echo ""
      exit 1
    fi

    echo ""
    echo "  🔍 ramu ask — searching for: $query"
    echo "  ────────────────────────────────────────────────"

    if ollama_check; then
      prompt="You are a SQL query helper. Given a user question about their files, generate a SQLite WHERE clause to search a table with columns: src (original filepath), dst (current filepath).
Respond with ONLY the WHERE clause, no SELECT, no semicolon, no explanation.
Use LIKE with % wildcards for fuzzy matching. Use lowercase in LIKE patterns. Use OR to combine multiple conditions.

Examples:
\"where is my resume\" -> lower(dst) LIKE '%resume%' OR lower(dst) LIKE '%cv%'
\"tax documents\" -> lower(dst) LIKE '%tax%' OR lower(dst) LIKE '%invoice%' OR lower(dst) LIKE '%receipt%'
\"python files\" -> lower(dst) LIKE '%.py' OR lower(dst) LIKE '%python%'
\"images from vacation\" -> lower(dst) LIKE '%vacation%' AND lower(dst) LIKE '%image%'

User question: $query"

      where_clause=$(ollama_ask "$prompt")

      if [ $? -ne 0 ] || [ -z "$where_clause" ] || ! validate_where "$where_clause"; then
        echo "  (AI query failed — falling back to keyword search)"
        where_clause=""
      fi
    else
      echo "  (Ollama offline — using keyword search)"
      where_clause=""
    fi

    # Fallback: simple keyword search
    if [ -z "$where_clause" ]; then
      # Split query into keywords, build LIKE chain
      where_clause=""
      for word in $query; do
        word=$(lower "$word")
        if [ -n "$where_clause" ]; then
          where_clause="$where_clause OR lower(dst) LIKE '%$word%'"
        else
          where_clause="lower(dst) LIKE '%$word%'"
        fi
      done
    fi

    # Also search file_descriptions if populated
    desc_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM file_descriptions;" 2>/dev/null)

    results=$(sqlite3 -separator "|" "$DB" \
      "SELECT DISTINCT dst FROM moves WHERE $where_clause ORDER BY id DESC LIMIT 25;" 2>/dev/null)

    if [ -n "$results" ] && [ "$desc_count" -gt 0 ]; then
      # Also search descriptions
      desc_results=$(sqlite3 -separator "|" "$DB" \
        "SELECT filepath FROM file_descriptions WHERE lower(description) LIKE '%$(lower "$query")%' OR lower(ai_category) LIKE '%$(lower "$query")%' LIMIT 10;" 2>/dev/null)
      if [ -n "$desc_results" ]; then
        results="$results
$desc_results"
      fi
    fi

    if [ -z "$results" ]; then
      echo ""
      echo "  No files found matching your query."
    else
      found=0
      printf '%s\n' "$results" | sort -u | while IFS='|' read -r filepath; do
        [ -z "$filepath" ] && continue
        found=$((found + 1))
        fname=$(basename "$filepath")
        dir=$(basename "$(dirname "$filepath")")
        if [ -e "$filepath" ]; then
          printf "  📄 %-45s  in %s\n" "$fname" "$dir"
        else
          printf "  📄 %-45s  in %s  (moved/deleted)\n" "$fname" "$dir"
        fi
      done
    fi
    echo ""
    exit 0
    ;;

  # ── AI: generate file descriptions ──────────────────────────────────────────
  describe)
    if ! ollama_check; then
      echo ""
      echo "  ❌ Ollama is not running at $OLLAMA_URL"
      echo "     Start it with: ollama serve"
      echo ""
      exit 1
    fi

    target_folder="${2:-}"
    limit="${3:-50}"

    echo ""
    echo "  🤖 ramu describe — generating AI descriptions"
    echo "  ────────────────────────────────────────────────"

    count=0; described=0

    # Determine search path
    if [ -n "$target_folder" ]; then
      search_path="$DOWNLOADS/$target_folder"
      if [ ! -d "$search_path" ]; then
        echo "  ❌ Folder not found: $target_folder"
        exit 1
      fi
    else
      search_path="$DOWNLOADS"
    fi

    while IFS= read -r -d '' f; do
      [ "$count" -ge "$limit" ] && break

      fname=$(basename "$f")
      fpath="$f"

      # Skip if already described
      existing=$(sqlite3 "$DB" "SELECT description FROM file_descriptions WHERE filepath='$(sql_esc "$fpath")' AND description IS NOT NULL;" 2>/dev/null)
      [ -n "$existing" ] && continue

      count=$((count + 1))

      # Determine the ramu folder this file is in
      rel="${f#$DOWNLOADS/}"
      folder=$(printf '%s' "$rel" | cut -d'/' -f1)

      prompt="Generate a short, one-line description (under 80 characters) for a file based on its name and location. Be specific and useful. Respond with ONLY the description, nothing else.

Examples:
Filepath: Downloads/01 PDFs/Receipts & Invoices/amazon_order_2024_03_15.pdf → Amazon purchase receipt from March 2024
Filepath: Downloads/07 Images/JPEG/IMG_20240315_beach.jpg → Beach photo taken in March 2024
Filepath: Downloads/17 Backend & Systems/auth_middleware.py → Python authentication middleware module

Filepath: Downloads/$rel"

      desc=$(ollama_ask "$prompt")
      if [ $? -ne 0 ] || [ -z "$desc" ]; then
        printf "  ⚠️  %-40s  (AI request failed)\n" "$fname"
        continue
      fi

      # Clean and truncate
      desc=$(printf '%s' "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 120)

      sqlite3 "$DB" "INSERT OR REPLACE INTO file_descriptions (filepath, filename, folder, description)
        VALUES ('$(sql_esc "$fpath")', '$(sql_esc "$fname")', '$(sql_esc "$folder")', '$(sql_esc "$desc")');"

      described=$((described + 1))
      printf "  %-40s  %s\n" "$fname" "$desc"

    done < <(find "$search_path" -type f -print0 2>/dev/null)

    echo ""
    echo "  ✅ Described $described files"
    echo ""
    exit 0
    ;;

esac

# ─────────────────────────────────────────────────────────────────────────────
# RUN — create session
# ─────────────────────────────────────────────────────────────────────────────
SESSION_ID=$(sqlite3 "$DB" \
  "INSERT INTO sessions (ts, dir) VALUES ('$(date "+%Y-%m-%d %H:%M:%S")', '$(sql_esc "$DOWNLOADS")');
   SELECT last_insert_rowid();")

# ─────────────────────────────────────────────────────────────────────────────
# PASS 1 — category definitions (parallel arrays, bash 3+ / zsh / sh)
# ─────────────────────────────────────────────────────────────────────────────
FOLDER_NAMES=(); FOLDER_EXTS=()
add() { FOLDER_NAMES+=("$1"); FOLDER_EXTS+=("$2"); }

# ── Documents ────────────────────────────────────────────────────────────────
add "01 PDFs"              "pdf"
add "02 Word Documents"    "doc docx odt fodt ott rtf wpd wps sxw abw zabw"
add "03 Spreadsheets"      "xls xlsx ods fods ots csv tsv numbers xlsm xlsb xltx xltm"
add "04 Presentations"     "ppt pptx odp fodp otp key pps ppsx"
add "05 Notes & Text"      "txt text md markdown mdx wiki rst asciidoc adoc org nfo me readme"
add "06 eBooks & Comics"   "epub mobi azw azw3 fb2 fb3 lit lrf djvu cbr cbz cb7 cbt"
# ── Media ────────────────────────────────────────────────────────────────────
add "07 Images"            "png jpg jpeg jfif jpe heic heif webp gif svg svgz bmp dib tiff tif ico icns ppm pgm pbm tga wbmp avif jxl apng"
add "08 RAW Photos"        "raw cr2 cr3 crw nef nrw arw srf sr2 dng orf rw2 rwl pef ptx r3d 3fr mef mos mrw x3f erf fff kdc dcr bay"
add "09 Videos"            "mp4 m4v mov avi mkv wmv flv webm 3gp 3g2 ogv ts mts m2ts vob rm rmvb asf f4v divx xvid mpg mpeg amv mxf"
add "10 Audio"             "mp3 wav aac m4a flac ogg oga opus wma aiff aif alac ape wv mpc mid midi gsm dss dvf msv vox amr awb"
add "11 Subtitles"         "srt ass ssa vtt sub sbv smi ttml dfxp lrc"
add "12 Playlists"         "m3u m3u8 pls xspf wpl asx"
# ── Design ───────────────────────────────────────────────────────────────────
add "13 Design Files"      "fig figma sketch xd afdesign afphoto afpub aftemplate studio procreate clip csp sai sai2 kra mypaint"
add "14 Adobe Files"       "psd psb ai eps indd inx idml fla swf aep aet prproj mogrt ppro aepx drp"
add "15 3D Models & CAD"   "gltf glb obj fbx dwg dxf ifc stl ply blend step stp iges igs sat 3ds dae skp rvt rfa rte rft max c4d lwo lws abc usd usda usdc usdz x3d wrl"
# ── Code ─────────────────────────────────────────────────────────────────────
add "16 Web"               "html htm xhtml shtml css scss sass less styl stylus postcss js mjs cjs jsx ts tsx vue svelte astro"
add "17 Backend & Systems" "py pyc pyw pyi rb rbx rake gemspec php php3 php4 php5 php7 phtml java class jar war ear go rs c cc cxx cpp h hpp hxx cs vb fs kt kts swift m mm scala clj edn ex exs erl hrl hs lhs purs dart nim zig v lua tcl awk sed f f90 f95 for"
add "18 Scripts & Shell"   "sh bash zsh fish ksh csh dash ps1 psm1 psd1 bat cmd vbs wsf make cmake gradle rakefile"
add "19 Config & Infra"    "json jsonc json5 toml yaml yml xml plist ini cfg conf rc config env lock lockb dockerfile dockerignore vagrantfile tf tfvars hcl nginx htaccess gitignore editorconfig babelrc eslintrc prettierrc nvmrc tsconfig jsconfig"
add "20 Queries & Markup"  "sql sqlite graphql gql sparql proto thrift avsc wsdl dtd xsl xslt xsd tex latex cls sty bst bib"
# ── Archives ─────────────────────────────────────────────────────────────────
add "21 Archives"          "zip tar gz tgz bz2 bz tbz tbz2 xz txz zst lz lzma lzo 7z rar cab arj arc ace lha lzh war jar ear aar"
add "22 Disk Images"       "iso img bin cue nrg mdf mds ccd sub vmdk vhd vhdx vdi ova ovf qcow2 hdd"
add "23 Installers"        "dmg pkg mpkg app exe msi msix appx appxbundle deb rpm snap flatpak appimage apk xapk ipa obb"
# ── Data & Science ───────────────────────────────────────────────────────────
add "24 Data & Databases"  "db sqlite sqlite3 mdb accdb realm parquet orc feather arrow avro ndjson jsonl geojson topojson kml kmz gpx shp dbf shx prj qgis vcf ics vcard"
add "25 ML & AI Models"    "ipynb pkl pickle joblib pt pth bin onnx h5 hdf hdf5 keras safetensors gguf ggml model weights ckpt checkpoint tflite mlmodel coreml"
add "26 Scientific"        "mat nc netcdf fits fit fts hdf4 sav por spss dta rdata rds rda wf1 jmp"
add "27 Medical Imaging"   "dcm dicom nii mgh mhd mha"
# ── Security ─────────────────────────────────────────────────────────────────
add "28 Certificates & Keys" "pem cer crt csr key pfx p12 p7b p7c p7r p8 jks der gpg asc pgp pub sig"
# ── Communication ────────────────────────────────────────────────────────────
add "29 Email & Calendar"  "eml emlx msg mbox pst ost mbx ics ical ifb vcs"
# ── Misc ─────────────────────────────────────────────────────────────────────
add "30 Fonts"             "ttf otf woff woff2 eot pfb pfm afm tfm vf fon fnt"
add "31 Executables"       "out a so dylib dll lib sys ko elf axf hex srec"
add "32 Virtual Machines"  "ova ovf vmx vmxf vmsd nvram vbox vbox-prev box vagrant"
add "33 Game & ROM Files"  "rom nes smc sfc gb gbc gba nds wad pk3 vpk gcm wbfs z64 v64 n64 smd gen"
add "34 Backup & Temp"     "bak backup old orig temp tmp swp swo"
add "35 Torrent & P2P"     "torrent part crdownload aria2"
add "36 Shortcuts & Links" "url webloc lnk desktop alias symlink"
add "37 Patch & Diff"      "patch diff rej"
add "38 Logs"              "log logs err crash dump dmp trace prof"

# ─────────────────────────────────────────────────────────────────────────────
# PASS 1 — sort root files into main folders
# ─────────────────────────────────────────────────────────────────────────────

# Build a lookup: extension -> folder name
# We write a temp file since we can't use assoc arrays portably
EXT_MAP=$(mktemp)
for i in "${!FOLDER_NAMES[@]}"; do
  folder="${FOLDER_NAMES[$i]}"
  for ext in ${FOLDER_EXTS[$i]}; do
    echo "$ext|$folder" >> "$EXT_MAP"
  done
done

mkdir -p "$DOWNLOADS/39 Other"
for i in "${!FOLDER_NAMES[@]}"; do
  mkdir -p "$DOWNLOADS/${FOLDER_NAMES[$i]}"
done

# Process each root-level file
while IFS= read -r -d '' f; do
  ext=$(file_ext "$f")
  # Look up folder for this extension
  target=$(grep "^${ext}|" "$EXT_MAP" | head -1 | cut -d'|' -f2-)
  if [ -n "$target" ]; then
    rec_mv "$f" "$DOWNLOADS/$target"
  else
    rec_mv "$f" "$DOWNLOADS/39 Other"
  fi
done < <(find "$DOWNLOADS" -maxdepth 1 -type f -print0)

# Unmatched folders → 39 Other
while IFS= read -r -d '' d; do
  name=$(basename "$d")
  case "$name" in
    [0-9][0-9]\ *) continue ;;  # skip our numbered folders
  esac
  rec_mv "$d" "$DOWNLOADS/39 Other"
done < <(find "$DOWNLOADS" -maxdepth 1 -mindepth 1 -type d -print0)

rm -f "$EXT_MAP"

# ─────────────────────────────────────────────────────────────────────────────
# PASS 2 — sub-sort large folders
# ─────────────────────────────────────────────────────────────────────────────

# Move files in $base whose extension matches into $base/$sub
sub_by_ext() {
  local base="$1" sub="$2"; shift 2
  mkdir -p "$base/$sub"
  while IFS= read -r -d '' f; do
    ext=$(file_ext "$f")
    for e in "$@"; do
      if [ "$ext" = "$e" ]; then
        rec_mv "$f" "$base/$sub"
        break
      fi
    done
  done < <(find "$base" -maxdepth 1 -type f -print0)
}

# Move files in $base whose lowercase name contains any keyword into $base/$sub
sub_by_name() {
  local base="$1" sub="$2"; shift 2
  mkdir -p "$base/$sub"
  while IFS= read -r -d '' f; do
    name=$(lower "$(basename "$f")")
    for kw in "$@"; do
      case "$name" in
        *"$kw"*)
          rec_mv "$f" "$base/$sub"
          break
          ;;
      esac
    done
  done < <(find "$base" -maxdepth 1 -type f -print0)
}

# Move all remaining root files in $base to $base/$sub
sub_rest() {
  local base="$1" sub="$2"
  mkdir -p "$base/$sub"
  while IFS= read -r -d '' f; do
    rec_mv "$f" "$base/$sub"
  done < <(find "$base" -maxdepth 1 -type f -print0)
}

# ── 01 PDFs ──────────────────────────────────────────────────────────────────
PDF="$DOWNLOADS/01 PDFs"
sub_by_name "$PDF" "Statements & Bank"   "statement" "cardnet" "acct" "account" "bank" "transaction" "passbook" "ledger" "balance"
sub_by_name "$PDF" "Receipts & Invoices" "receipt" "invoice" "fee_receipt" "payment" "fee" "bill" "purchase" "order" "tax"
sub_by_name "$PDF" "Agreements & Legal"  "agreement" "contract" "legal" "terms" "t&c" "nda" "policy" "mou"
sub_by_name "$PDF" "Books & Education"   "python" "hacking" "pentest" "machine learning" "deep learning" "algorithm" "design pattern" "system design" "dsa" "data structure" "programming" "handbook" "guide" "tutorial" "course" "lecture" "chapter" "book" "learn"
sub_by_name "$PDF" "Resumes & CVs"       "resume" "_cv" "-cv" "curriculum" "cover_letter" "coverletter"
sub_by_name "$PDF" "Tickets & Passes"    "ticket" "boarding" "pass" "booking" "flight" "train" "bus" "reservation" "pnr"
sub_by_name "$PDF" "Reports & Research"  "report" "research" "paper" "thesis" "dissertation" "analysis" "audit" "summary" "review"
sub_by_name "$PDF" "Certificates & IDs"  "certificate" "cert" "aadhar" "aadhaar" "pan" "passport" "id_card" "marksheet" "degree"
sub_rest    "$PDF" "Other PDFs"

# ── 07 Images ────────────────────────────────────────────────────────────────
IMG="$DOWNLOADS/07 Images"
sub_by_ext "$IMG" "PNG"      png
sub_by_ext "$IMG" "JPEG"     jpg jpeg jfif jpe
sub_by_ext "$IMG" "Vectors"  svg svgz eps
sub_by_ext "$IMG" "Web"      webp avif jxl apng
sub_by_ext "$IMG" "Animated" gif
sub_by_ext "$IMG" "Apple"    heic heif
sub_by_ext "$IMG" "Icons"    ico icns
sub_by_ext "$IMG" "Other"    bmp dib tiff tif ppm pgm pbm tga wbmp
sub_rest   "$IMG" "Other"

# ── 09 Videos ────────────────────────────────────────────────────────────────
VID="$DOWNLOADS/09 Videos"
sub_by_name "$VID" "Screen Recordings" "screen recording" "screenrecording" "screen_recording" "screencast"
sub_by_ext  "$VID" "MOV"   mov
sub_by_ext  "$VID" "MP4"   mp4 m4v
sub_by_ext  "$VID" "MKV"   mkv
sub_by_ext  "$VID" "WebM"  webm
sub_by_ext  "$VID" "Other" avi wmv flv 3gp ogv ts mts vob rm rmvb mpg mpeg
sub_rest    "$VID" "Other"

# ── 10 Audio ─────────────────────────────────────────────────────────────────
AUD="$DOWNLOADS/10 Audio"
sub_by_ext "$AUD" "MP3"   mp3
sub_by_ext "$AUD" "WAV"   wav aiff aif
sub_by_ext "$AUD" "AAC"   aac m4a
sub_by_ext "$AUD" "FLAC"  flac alac ape wv
sub_by_ext "$AUD" "Other" ogg oga opus wma amr awb mid midi
sub_rest   "$AUD" "Other"

# ── 15 3D Models & CAD ───────────────────────────────────────────────────────
TDM="$DOWNLOADS/15 3D Models & CAD"
sub_by_ext "$TDM" "CAD & Architecture" dwg dxf ifc rvt rfa rte rft step stp iges igs sat skp
sub_by_ext "$TDM" "3D Models"          gltf glb obj fbx dae 3ds abc usd usda usdc usdz x3d wrl lwo lws
sub_by_ext "$TDM" "Print Files"        stl ply
sub_by_ext "$TDM" "Blender"            blend
sub_rest   "$TDM" "Other"

# ── 19 Config & Infra ────────────────────────────────────────────────────────
CFG="$DOWNLOADS/19 Config & Infra"
sub_by_name "$CFG" "Docker"         "docker"
sub_by_name "$CFG" "Secrets & Keys" "secret" "credential" "client_secret" "api_key" "apikey" "token"
sub_by_name "$CFG" "Kubernetes"     "kube" "k8s" "vke" "helm" "namespace" "ingress" "deployment"
sub_by_name "$CFG" "Data Files"     "annotation" "processed" "floor" "data"
sub_rest    "$CFG" "Other Config"

# ── 21 Archives ──────────────────────────────────────────────────────────────
ARC="$DOWNLOADS/21 Archives"
sub_by_name "$ARC" "WhatsApp Exports" "whatsapp"
sub_by_name "$ARC" "iOS & Mobile"     "ios" "iphone" "ipad" "android" "mobile" "mipl"
sub_by_name "$ARC" "Google Drive"     "drive-download" "google drive" "gdrive"
sub_by_name "$ARC" "Projects"         "flask" "hexaware" "observance" "pokechat" "qr" "status" "blackberr"
sub_rest    "$ARC" "Other Archives"

# ─────────────────────────────────────────────────────────────────────────────
# Finalize
# ─────────────────────────────────────────────────────────────────────────────

# Remove empty dirs
find "$DOWNLOADS" -mindepth 1 -maxdepth 2 -type d -empty -delete 2>/dev/null

# Update session moved count
sqlite3 "$DB" "UPDATE sessions SET moved=$moved WHERE id=$SESSION_ID;"

# Prune: keep only the 4 most recent sessions
sqlite3 "$DB" "
PRAGMA foreign_keys=ON;
DELETE FROM sessions WHERE id NOT IN (
  SELECT id FROM sessions ORDER BY id DESC LIMIT 4
);"

echo ""
echo "  ✅ ramu  session #$SESSION_ID  —  $moved files organized"
echo "     Run 'ramu history' to see all sessions  |  'ramu undo' to reverse"
echo ""
