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
);"

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
    echo "  ENVIRONMENT"
    echo "    RAMU_DIR=<path>   Override target directory (default: ~/Downloads)"
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

esac

# ─────────────────────────────────────────────────────────────────────────────
# RUN — create session
# ─────────────────────────────────────────────────────────────────────────────
SESSION_ID=$(sqlite3 "$DB" \
  "INSERT INTO sessions (ts, dir) VALUES ('$(date "+%Y-%m-%d %H:%M:%S")', '$(sql_esc "$DOWNLOADS")');
   SELECT last_insert_rowid();")

# Recorded move — logs src/dst to SQLite
rec_mv() {
  local src="$1" dst_dir="$2"
  local dst="$dst_dir/$(basename "$src")"
  mv "$src" "$dst_dir/" && {
    sqlite3 "$DB" "INSERT INTO moves (session_id,src,dst) VALUES ($SESSION_ID,'$(sql_esc "$src")','$(sql_esc "$dst")');"
    moved=$((moved + 1))
  }
}

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
