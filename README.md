# ramu

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

Your Downloads folder is a warzone. PDFs from 2022 vibing next to random `.dmg` files, screenshots you swore you'd delete, and that one `invoice_final_FINAL_v3.pdf`. We've all been there.

**ramu** is a no-nonsense shell script that sorts your `~/Downloads` into 38 clean folders — with sub-sorting for the messy ones (PDFs by keyword, images by format, archives by source). Every move is tracked in SQLite, so you can undo up to 4 sessions if ramu gets too enthusiastic.

Built for my own workflow, tuned to how I actually use my Mac. But it's just a shell script — crack it open and hack it to fit yours.

---

## Quick Start

**One-line install:**
```bash
curl -fsSL https://raw.githubusercontent.com/imkuldeepahlawat/ramu/main/install.sh | bash
```

**Or clone and setup:**
```bash
git clone https://github.com/imkuldeepahlawat/ramu.git
cd ramu
bash setup.sh
```

Then reload your shell (`source ~/.zshrc` or `source ~/.bashrc`) — you now have `ramu` as an alias and a daily 9am cron job keeping things tidy.

**Needs:** macOS, sqlite3, curl, jq (all pre-installed on macOS), bash 3.2+ or zsh or sh — whatever you run, ramu runs.

**AI features need:** [Ollama](https://ollama.com/download) (local install) or Docker — ramu can manage its own Ollama container.

---

## What Can It Do

```bash
ramu              # sort the chaos
ramu help         # the full menu
ramu history      # see last 4 runs
ramu undo         # oops, bring it all back
ramu undo 2       # undo a specific session
```

Want to point it at a different folder?
```bash
RAMU_DIR=~/Desktop ramu
```

---

## AI Powers

ramu uses [Ollama](https://ollama.com) to run a local AI model (mistral 7B by default) for smart file management. No cloud, no API keys, everything stays on your machine.

### Setup (pick one)

```bash
# Option A: Install Ollama locally
brew install ollama
ollama serve &
ollama pull mistral

# Option B: Let ramu handle it via Docker
ramu ai-start    # pulls and runs ollama/ollama in Docker, downloads model
ramu ai-stop     # stops the container (data preserved)
```

### Smart Sort — rescue files from "39 Other"

Files that don't match any extension rule end up in `39 Other`. AI analyzes them and suggests the right folder.

```bash
ramu ai-sort            # preview suggestions (dry run)
ramu ai-sort --apply    # actually move the files
ramu undo               # changed your mind? undo works as usual
```

For known extensions (`.dwg`, `.pdf`, `.xlsx`, etc.) ramu uses deterministic rule-based matching — instant, no hallucination. AI is only called for truly ambiguous files.

### Ask — natural language file search

```bash
ramu ask "where did my resume go"
ramu ask "club house plans"
ramu ask "tax documents"
```

Searches your move history using AI-powered query understanding. Falls back to keyword search if Ollama is offline.

### Describe — AI file descriptions

```bash
ramu describe              # describe all undescribed files
ramu describe "07 Images"  # target a specific folder
```

Generates one-line descriptions stored in SQLite, making `ramu ask` searches even better.

### Environment Variables

```bash
RAMU_OLLAMA_URL=http://localhost:11434   # default Ollama endpoint
RAMU_OLLAMA_MODEL=mistral:latest         # swap in any Ollama model
```

---

## Where Does Stuff Go

ramu doesn't just dump everything into "Documents" and call it a day. It actually thinks about it:

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
│   ├── PNG/  JPEG/  Vectors/  Web/
│   ├── Animated/  Apple/  Icons/
├── 08 RAW Photos/
├── 09 Videos/
│   ├── Screen Recordings/  MOV/  MP4/  MKV/  WebM/
├── 10 Audio/
│   ├── MP3/  WAV/  AAC/  FLAC/
├── 11 Subtitles/
├── 12 Playlists/
├── 13 Design Files/        .fig .sketch .xd .afdesign
├── 14 Adobe Files/         .psd .ai .indd .aep
├── 15 3D Models & CAD/
│   ├── CAD & Architecture/  3D Models/
│   ├── Print Files/  Blender/
├── 16 Web/                 .html .css .js .ts .vue
├── 17 Backend & Systems/   .py .go .rs .java .cpp
├── 18 Scripts & Shell/     .sh .zsh .ps1 .bat
├── 19 Config & Infra/
│   ├── Docker/  Kubernetes/
│   ├── Secrets & Keys/  Data Files/
├── 20 Queries & Markup/    .sql .graphql .proto .tex
├── 21 Archives/
│   ├── WhatsApp Exports/  iOS & Mobile/
│   ├── Google Drive/  Projects/
├── 22 Disk Images/
├── 23 Installers/          .dmg .pkg .exe .apk
├── 24 Data & Databases/    .parquet .geojson .gpx
├── 25 ML & AI Models/      .onnx .safetensors .gguf
├── 26 Scientific/
├── 27 Medical Imaging/
├── 28 Certificates & Keys/ .pem .crt .pfx .gpg
├── 29 Email & Calendar/
├── 30 Fonts/
├── 31 Executables/
├── 32 Virtual Machines/
├── 33 Game & ROM Files/
├── 34 Backup & Temp/
├── 35 Torrent & P2P/
├── 36 Shortcuts & Links/
├── 37 Patch & Diff/
├── 38 Logs/
└── 39 Other/               everything else lands here
```

---

## The Undo Safety Net

Every single file move gets logged to `~/scripts/ramu.db`. Not some of them — all of them.

```bash
ramu history
# #5  2026-03-27 12:18  841 files  ~/Downloads
# #4  2026-03-27 09:00  12 files   ~/Downloads

ramu undo        # bring back session #5
ramu undo 2      # bring back session #4, independently
```

Undos are isolated. Reversing session 2 doesn't touch session 1. ramu keeps the last 4 sessions and auto-prunes older ones.

---

## Runs While You Sleep

Setup drops a cron job that fires every morning at 9am:

```
0 9 * * * /bin/bash ~/scripts/ramu.sh >> ~/scripts/ramu.log 2>&1
```

Wake up to a clean Downloads. Every day. No effort.

---

## Hack It

This is a single `.sh` file. The folder categories, sub-sort keywords, extension mappings — it's all right there in `ramu.sh`. Don't like how PDFs are sorted? Change the keywords. Want to add a category for your weird `.xyz` files? Add one line. No config files, no YAML, no build step.

```bash
# adding a new category is literally one line:
add "40 My Custom Folder" "xyz abc def"
```

The sub-sort functions are just as simple — `sub_by_ext` sorts by file extension, `sub_by_name` sorts by keywords in the filename. Mix and match.

---

## License

MIT — do whatever you want with it.

