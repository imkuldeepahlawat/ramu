# ramu

A smart Downloads folder organizer for macOS with **SQLite-backed undo** (last 4 sessions).

Automatically sorts `~/Downloads` into 38 typed subfolders with keyword-aware sub-sorting for large categories. Runs daily via cron or on-demand.

---

## Install

```zsh
git clone https://github.com/imkuldeepahlawat/ramu.git
cd ramu
zsh setup.sh
source ~/.zshrc
```

**Requirements:** macOS, zsh, sqlite3 (pre-installed on macOS)

---

## Usage

```zsh
ramu              # organize ~/Downloads
ramu help         # show full help
ramu history      # show last 4 sessions
ramu undo         # undo most recent session
ramu undo 2       # undo 2nd most recent session
ramu undo 3|4     # undo 3rd or 4th most recent session
```

Override the target directory:
```zsh
RAMU_DIR=~/Desktop ramu
```

---

## Folder Structure

```
Downloads/
├── 01 PDFs/
│   ├── Statements & Bank/
│   ├── Receipts & Invoices/
│   ├── Agreements & Legal/
│   ├── Books & Education/
│   ├── Resumes & CVs/
│   ├── Tickets & Passes/
│   ├── Reports & Research/
│   ├── Certificates & IDs/
│   └── Other PDFs/
├── 02 Word Documents/
├── 03 Spreadsheets/
├── 04 Presentations/
├── 05 Notes & Text/
├── 06 eBooks & Comics/
├── 07 Images/
│   ├── PNG/
│   ├── JPEG/
│   ├── Vectors/
│   ├── Web/
│   ├── Animated/
│   ├── Apple/
│   └── Icons/
├── 08 RAW Photos/
├── 09 Videos/
│   ├── Screen Recordings/
│   ├── MOV/
│   ├── MP4/
│   ├── MKV/
│   └── WebM/
├── 10 Audio/
│   ├── MP3/
│   ├── WAV/
│   ├── AAC/
│   └── FLAC/
├── 11 Subtitles/
├── 12 Playlists/
├── 13 Design Files/        (.fig .sketch .xd .afdesign …)
├── 14 Adobe Files/         (.psd .ai .indd .aep …)
├── 15 3D Models & CAD/
│   ├── CAD & Architecture/ (.dwg .dxf .ifc .rvt …)
│   ├── 3D Models/          (.gltf .glb .obj .fbx …)
│   ├── Print Files/        (.stl .ply)
│   └── Blender/            (.blend)
├── 16 Web/                 (.html .css .js .ts .tsx .vue …)
├── 17 Backend & Systems/   (.py .go .rs .java .cpp …)
├── 18 Scripts & Shell/     (.sh .zsh .ps1 .bat …)
├── 19 Config & Infra/
│   ├── Docker/
│   ├── Kubernetes/
│   ├── Secrets & Keys/
│   └── Data Files/
├── 20 Queries & Markup/    (.sql .graphql .proto .tex …)
├── 21 Archives/
│   ├── WhatsApp Exports/
│   ├── iOS & Mobile/
│   ├── Google Drive/
│   └── Projects/
├── 22 Disk Images/
├── 23 Installers/          (.dmg .pkg .exe .apk .ipa …)
├── 24 Data & Databases/    (.parquet .geojson .gpx …)
├── 25 ML & AI Models/      (.onnx .safetensors .gguf …)
├── 26 Scientific/
├── 27 Medical Imaging/     (.dcm .nii …)
├── 28 Certificates & Keys/ (.pem .crt .pfx .gpg …)
├── 29 Email & Calendar/    (.eml .ics .vcf …)
├── 30 Fonts/
├── 31 Executables/
├── 32 Virtual Machines/
├── 33 Game & ROM Files/
├── 34 Backup & Temp/
├── 35 Torrent & P2P/
├── 36 Shortcuts & Links/
├── 37 Patch & Diff/
├── 38 Logs/
└── 39 Other/
```

---

## Undo

Every `mv` is recorded in `~/scripts/ramu.db`. Each run creates a session. Up to **4 sessions** are kept.

```zsh
ramu history
# #5  2026-03-27 12:18  841 files  ~/Downloads
# #4  2026-03-27 09:00  12 files   ~/Downloads

ramu undo      # restore session #5 files → ~/Downloads
ramu undo 2    # restore session #4 files → ~/Downloads (independent)
```

Each undo is **isolated** — reversing session 2 does not affect session 1.

---

## Cron

Setup installs a daily cron job at 9am:

```
0 9 * * * /bin/zsh ~/scripts/ramu.sh >> ~/scripts/ramu.log 2>&1
```

---

## Author

**Kuldeep Ahlawat** — [@imkuldeepahlawat](https://github.com/imkuldeepahlawat)
