#!/usr/bin/env zsh
# ramu — Downloads organizer with SQLite undo (last 4 sessions)
#
# Usage:
#   ramu                  — run organizer
#   ramu history          — show last 4 sessions
#   ramu undo             — undo most recent session
#   ramu undo 2           — undo 2nd most recent session
#   ramu undo 3 / 4       — undo 3rd / 4th most recent session

DOWNLOADS="${RAMU_DIR:-$HOME/Downloads}"
DB="$HOME/scripts/ramu.db"
SESSION_ID=""
moved=0

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
    echo "  ENVIRONMENT"
    echo "    RAMU_DIR=<path>   Override target directory (default: ~/Downloads)"
    echo ""
    exit 0
    ;;

  history)
    echo ""
    echo "  ramu — last 4 sessions"
    echo "  ────────────────────────────────────────────────"
    sqlite3 -separator " | " "$DB" "
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

    if [[ -z "$SESSION_ID" ]]; then
      echo "❌ No session found at position $N  (run 'ramu history' to see available sessions)"
      exit 1
    fi

    TS=$(sqlite3 "$DB" "SELECT ts FROM sessions WHERE id=$SESSION_ID;")
    COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM moves WHERE session_id=$SESSION_ID;")
    echo ""
    echo "  ↩️  Undoing session #$SESSION_ID  ($TS)  —  $COUNT files"
    echo "  ────────────────────────────────────────────────"

    undone=0
    missing=0
    # Reverse order so nested moves unwind correctly
    while IFS='|' read -r src dst; do
      if [[ -e "$dst" ]]; then
        mkdir -p "$(dirname "$src")"
        mv "$dst" "$src" && (( undone++ ))
      else
        echo "  ⚠️  missing: $(basename "$dst")  (skipped)"
        (( missing++ ))
      fi
    done < <(sqlite3 "$DB" \
      "SELECT src, dst FROM moves WHERE session_id=$SESSION_ID ORDER BY id DESC;")

    # Clean up empty ramu-created dirs
    find "$DOWNLOADS" -mindepth 1 -maxdepth 2 -type d -empty -delete 2>/dev/null

    # Remove session record (cascades to moves)
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
  "INSERT INTO sessions (ts, dir) VALUES ('$(date "+%Y-%m-%d %H:%M:%S")', '$DOWNLOADS');
   SELECT last_insert_rowid();")

# Recorded move — wraps every mv and logs src/dst to DB
rec_mv() {
  local src="$1" dst_dir="$2"
  local dst="$dst_dir/$(basename "$src")"
  mv "$src" "$dst_dir/" && {
    # Escape single quotes for SQLite by doubling them
    local s=$(printf '%s' "$src" | sed "s/'/''/g")
    local d=$(printf '%s' "$dst" | sed "s/'/''/g")
    sqlite3 "$DB" "INSERT INTO moves (session_id,src,dst) VALUES ($SESSION_ID,'$s','$d');"
    (( moved++ ))
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# PASS 1 — Sort root-level files by extension into main folders
# ─────────────────────────────────────────────────────────────────────────────
typeset -A FOLDERS
FOLDERS=(
  # ── Documents ──────────────────────────────────────────────────────────────
  "01 PDFs"               "pdf"
  "02 Word Documents"     "doc docx odt fodt ott rtf wpd wps sxw abw zabw"
  "03 Spreadsheets"       "xls xlsx ods fods ots csv tsv numbers xlsm xlsb xltx xltm"
  "04 Presentations"      "ppt pptx odp fodp otp key pps ppsx"
  "05 Notes & Text"       "txt text md markdown mdx wiki rst asciidoc adoc org nfo log me readme"
  "06 eBooks & Comics"    "epub mobi azw azw3 fb2 fb3 lit lrf djvu cbr cbz cb7 cbt"
  # ── Media ──────────────────────────────────────────────────────────────────
  "07 Images"             "png jpg jpeg jfif jpe heic heif webp gif svg svgz bmp dib tiff tif ico
                           icns ppm pgm pbm pnm xbm xpm pcx tga wbmp avif jxl apng"
  "08 RAW Photos"         "raw cr2 cr3 crw nef nrw arw srf sr2 dng orf rw2 rwl pef ptx r3d
                           3fr mef mos mrw x3f erf fff kdc dcr bay"
  "09 Videos"             "mp4 m4v mov avi mkv wmv flv webm 3gp 3g2 ogv ts mts m2ts m2t
                           vob rm rmvb asf f4v divx xvid mpg mpeg amv mxf roq"
  "10 Audio"              "mp3 wav aac m4a flac ogg oga opus wma aiff aif alac ape wv mpc
                           mid midi gsm dss dvf msv vox amr awb"
  "11 Subtitles"          "srt ass ssa vtt sub sbv smi ttml dfxp lrc"
  "12 Playlists"          "m3u m3u8 pls xspf wpl asx"
  # ── Design & Creative ──────────────────────────────────────────────────────
  "13 Design Files"       "fig figma sketch xd afdesign afphoto afpub aftemplate studio procreate
                           clip csp sai sai2 kra mypaint"
  "14 Adobe Files"        "psd psb ai eps indd inx idml fla swf aep aet prproj mogrt ppro aepx drp"
  "15 3D Models & CAD"    "gltf glb obj fbx dwg dxf ifc stl ply blend step stp iges igs sat
                           3ds dae skp rvt rfa rte rft max c4d lwo lws lxo hrc scn abc
                           usd usda usdc usdz x3d wrl"
  # ── Code & Dev ─────────────────────────────────────────────────────────────
  "16 Web"                "html htm xhtml shtml css scss sass less styl stylus postcss
                           js mjs cjs jsx ts tsx vue svelte astro angular"
  "17 Backend & Systems"  "py pyc pyw pyi rb rbx rake gemspec
                           php php3 php4 php5 php7 phtml
                           java class jar war ear
                           go rs c cc cxx cpp c++ h hpp hxx
                           cs vb fs fsi fsx fsscript
                           kt kts swift m mm
                           scala clj cljs cljc edn
                           ex exs erl hrl hs lhs purs
                           dart nim zig v lua tcl awk sed
                           f f90 f95 f03 f08 for"
  "18 Scripts & Shell"    "sh bash zsh fish ksh csh dash
                           ps1 psm1 psd1 bat cmd vbs wsf
                           make makefile cmake gradle rakefile guardfile"
  "19 Config & Infra"     "json jsonc json5 toml yaml yml xml
                           plist ini cfg conf rc config
                           env env.example env.local env.test env.production
                           lock lockb dockerfile dockerignore vagrantfile
                           tf tfvars hcl helmfile
                           nginx apacheconf htaccess
                           gitignore gitattributes gitmodules
                           editorconfig babelrc eslintrc prettierrc stylelintrc
                           nvmrc node-version ruby-version python-version
                           tsconfig jsconfig"
  "20 Queries & Markup"   "sql sqlite graphql gql sparql proto thrift avsc
                           wsdl dtd xsl xslt xsd tex latex cls sty bst bib"
  # ── Archives & Installers ──────────────────────────────────────────────────
  "21 Archives"           "zip tar gz tgz bz2 bz tbz tbz2 xz txz zst lz lzma lzo
                           7z rar cab arj arc ace lha lzh war jar ear aar"
  "22 Disk Images"        "iso img bin cue nrg mdf mds ccd sub vmdk vhd vhdx vdi ova ovf qcow2 hdd"
  "23 Installers"         "dmg pkg mpkg app exe msi msix appx appxbundle
                           deb rpm snap flatpak appimage apk xapk ipa obb"
  # ── Data & Science ─────────────────────────────────────────────────────────
  "24 Data & Databases"   "db sqlite sqlite3 mdb accdb realm
                           parquet orc feather arrow avro
                           ndjson jsonl geojson topojson
                           kml kmz gpx shp dbf shx prj qgis vcf ics vcard"
  "25 ML & AI Models"     "ipynb pkl pickle joblib pt pth bin onnx
                           h5 hdf hdf5 keras tf safetensors gguf ggml
                           model weights ckpt checkpoint tflite mlmodel coreml"
  "26 Scientific"         "mat nc netcdf fits fit fts hdf4 sav por spss dta rdata rds rda wf1 jmp"
  "27 Medical Imaging"    "dcm dicom nii mgh mhd mha"
  # ── Security ───────────────────────────────────────────────────────────────
  "28 Certificates & Keys" "pem cer crt csr key pfx p12 p7b p7c p7r p8 jks der gpg asc pgp pub sig"
  # ── Communication ──────────────────────────────────────────────────────────
  "29 Email & Calendar"   "eml emlx msg mbox pst ost mbx ics ical ifb vcs"
  # ── Fonts ──────────────────────────────────────────────────────────────────
  "30 Fonts"              "ttf otf woff woff2 eot pfb pfm afm tfm vf fon fnt"
  # ── System & Misc ──────────────────────────────────────────────────────────
  "31 Executables"        "out a so dylib dll lib sys ko o obj elf axf hex srec"
  "32 Virtual Machines"   "ova ovf vmx vmxf vmsd nvram vbox vbox-prev box vagrant"
  "33 Game & ROM Files"   "rom nes smc sfc gb gbc gba nds wad pk3 vpk gcm wbfs z64 v64 n64 smd gen"
  "34 Backup & Temp"      "bak backup old orig temp tmp swp swo"
  "35 Torrent & P2P"      "torrent part crdownload aria2"
  "36 Shortcuts & Links"  "url webloc lnk desktop alias symlink"
  "37 Patch & Diff"       "patch diff rej"
  "38 Logs"               "log logs err crash dump dmp trace prof"
)

for folder exts in ${(kv)FOLDERS}; do
  mkdir -p "$DOWNLOADS/$folder"
  for ext in ${=exts}; do
    for f in "$DOWNLOADS"/*(.N); do
      [[ "${f:e:l}" == "$ext" ]] || continue
      rec_mv "$f" "$DOWNLOADS/$folder"
    done
  done
done

# Unmatched files → 39 Other
mkdir -p "$DOWNLOADS/39 Other"
for f in "$DOWNLOADS"/*(.N); do
  rec_mv "$f" "$DOWNLOADS/39 Other"
done

# Unmatched folders → 39 Other
for d in "$DOWNLOADS"/*(/.N); do
  [[ "$(basename "$d")" =~ ^[0-9]{2}\ .+ ]] && continue
  rec_mv "$d" "$DOWNLOADS/39 Other"
done

# ─────────────────────────────────────────────────────────────────────────────
# PASS 2 — Sub-sort large folders
# ─────────────────────────────────────────────────────────────────────────────

sub_by_ext() {
  local base="$1" sub="$2"; shift 2
  mkdir -p "$base/$sub"
  for ext in "$@"; do
    for f in "$base"/*(.N); do
      [[ "${f:e:l}" == "$ext" ]] && rec_mv "$f" "$base/$sub"
    done
  done
}

sub_by_name() {
  local base="$1" sub="$2"; shift 2
  mkdir -p "$base/$sub"
  for f in "$base"/*(.N); do
    local name="${$(basename "$f"):l}"
    for kw in "$@"; do
      if [[ "$name" == *"$kw"* ]]; then
        rec_mv "$f" "$base/$sub"
        break
      fi
    done
  done
}

# ── 01 PDFs ──────────────────────────────────────────────────────────────────
PDF="$DOWNLOADS/01 PDFs"
sub_by_name "$PDF" "Statements & Bank"   "statement" "cardnet" "acct" "account" "bank" "transaction" "passbook" "ledger" "balance"
sub_by_name "$PDF" "Receipts & Invoices" "receipt" "invoice" "fee_receipt" "payment" "fee" "bill" "purchase" "order" "tax"
sub_by_name "$PDF" "Agreements & Legal"  "agreement" "contract" "legal" "terms" "t&c" "nda" "policy" "mou"
sub_by_name "$PDF" "Books & Education"   "python" "hacking" "pentest" "machine learning" "deep learning" "algorithm" \
                                          "design pattern" "system design" "dsa" "data structure" "programming" \
                                          "handbook" "guide" "tutorial" "course" "lecture" "chapter" "book" "learn"
sub_by_name "$PDF" "Resumes & CVs"       "resume" "_cv" "-cv" "curriculum" "cover_letter" "coverletter"
sub_by_name "$PDF" "Tickets & Passes"    "ticket" "boarding" "pass" "booking" "flight" "train" "bus" "reservation" "pnr"
sub_by_name "$PDF" "Reports & Research"  "report" "research" "paper" "thesis" "dissertation" "analysis" "audit" "summary" "review"
sub_by_name "$PDF" "Certificates & IDs"  "certificate" "cert" "aadhar" "aadhaar" "pan" "passport" "id_card" "marksheet" "degree"
mkdir -p "$PDF/Other PDFs"
for f in "$PDF"/*(.N); do rec_mv "$f" "$PDF/Other PDFs"; done

# ── 07 Images ────────────────────────────────────────────────────────────────
IMG="$DOWNLOADS/07 Images"
sub_by_ext "$IMG" "PNG"     png
sub_by_ext "$IMG" "JPEG"    jpg jpeg jfif jpe
sub_by_ext "$IMG" "Vectors" svg svgz eps
sub_by_ext "$IMG" "Web"     webp avif jxl apng
sub_by_ext "$IMG" "Animated" gif
sub_by_ext "$IMG" "Apple"   heic heif
sub_by_ext "$IMG" "Icons"   ico icns
sub_by_ext "$IMG" "Other"   bmp dib tiff tif ppm pgm pbm pnm xbm xpm pcx tga wbmp
mkdir -p "$IMG/Other"
for f in "$IMG"/*(.N); do rec_mv "$f" "$IMG/Other"; done

# ── 09 Videos ────────────────────────────────────────────────────────────────
VID="$DOWNLOADS/09 Videos"
sub_by_name "$VID" "Screen Recordings" "screen recording" "screenrecording" "screen_recording" "screencast"
sub_by_ext  "$VID" "MOV"   mov
sub_by_ext  "$VID" "MP4"   mp4 m4v
sub_by_ext  "$VID" "MKV"   mkv
sub_by_ext  "$VID" "WebM"  webm
sub_by_ext  "$VID" "Other" avi wmv flv 3gp ogv ts mts vob rm rmvb mpg mpeg
mkdir -p "$VID/Other"
for f in "$VID"/*(.N); do rec_mv "$f" "$VID/Other"; done

# ── 15 3D Models & CAD ───────────────────────────────────────────────────────
TDM="$DOWNLOADS/15 3D Models & CAD"
sub_by_ext "$TDM" "CAD & Architecture" dwg dxf ifc rvt rfa rte rft step stp iges igs sat skp
sub_by_ext "$TDM" "3D Models"          gltf glb obj fbx dae 3ds abc usd usda usdc usdz x3d wrl lwo lws
sub_by_ext "$TDM" "Print Files"        stl ply
sub_by_ext "$TDM" "Blender"            blend
sub_by_ext "$TDM" "Other"              max c4d
mkdir -p "$TDM/Other"
for f in "$TDM"/*(.N); do rec_mv "$f" "$TDM/Other"; done

# ── 21 Archives ──────────────────────────────────────────────────────────────
ARC="$DOWNLOADS/21 Archives"
sub_by_name "$ARC" "WhatsApp Exports" "whatsapp"
sub_by_name "$ARC" "iOS & Mobile"     "ios" "iphone" "ipad" "android" "mobile" "mipl"
sub_by_name "$ARC" "Google Drive"     "drive-download" "google drive" "gdrive"
sub_by_name "$ARC" "Projects"         "flask" "hexaware" "observance" "pokechat" "qr" "status" "blackberr"
mkdir -p "$ARC/Other Archives"
for f in "$ARC"/*(.N); do rec_mv "$f" "$ARC/Other Archives"; done

# ── 19 Config & Infra ────────────────────────────────────────────────────────
CFG="$DOWNLOADS/19 Config & Infra"
sub_by_name "$CFG" "Docker"         "docker"
sub_by_name "$CFG" "Secrets & Keys" "secret" "credential" "client_secret" "api_key" "apikey" "token"
sub_by_name "$CFG" "Kubernetes"     "kube" "k8s" "vke" "helm" "namespace" "ingress" "deployment"
sub_by_name "$CFG" "Data Files"     "annotation" "processed" "floor" "data"
mkdir -p "$CFG/Other Config"
for f in "$CFG"/*(.N); do rec_mv "$f" "$CFG/Other Config"; done

# ── 10 Audio ─────────────────────────────────────────────────────────────────
AUD="$DOWNLOADS/10 Audio"
sub_by_ext "$AUD" "MP3"   mp3
sub_by_ext "$AUD" "WAV"   wav aiff aif
sub_by_ext "$AUD" "AAC"   aac m4a
sub_by_ext "$AUD" "FLAC"  flac alac ape wv
sub_by_ext "$AUD" "Other" ogg oga opus wma amr awb mid midi
mkdir -p "$AUD/Other"
for f in "$AUD"/*(.N); do rec_mv "$f" "$AUD/Other"; done

# ─────────────────────────────────────────────────────────────────────────────
# Finalize
# ─────────────────────────────────────────────────────────────────────────────

# Remove empty dirs
find "$DOWNLOADS" -mindepth 1 -maxdepth 2 -type d -empty -delete 2>/dev/null

# Update session moved count
sqlite3 "$DB" "UPDATE sessions SET moved=$moved WHERE id=$SESSION_ID;"

# Prune: keep only the 4 most recent sessions (cascade deletes their moves)
sqlite3 "$DB" "
PRAGMA foreign_keys=ON;
DELETE FROM sessions WHERE id NOT IN (
  SELECT id FROM sessions ORDER BY id DESC LIMIT 4
);"

echo ""
echo "  ✅ ramu  session #$SESSION_ID  —  $moved files organized"
echo "     Run 'ramu history' to see all sessions  |  'ramu undo' to reverse"
echo ""
