# DiskWise for macOS

Intelligent macOS disk analyzer and cleanup assistant. Scan drives, identify storage hotspots, detect duplicates, analyze media collections, and safely reclaim disk space using AI-powered recommendations.

Unlike traditional tools that only show category totals, DiskWise acts as an **AI storage consultant**:

- Surfaces duplicate videos, preview files, stale exports, and long-unaccessed media
- Estimates reclaimable space with actionable cleanup plans
- Moves files to Trash with preview and undo-friendly workflow

## Stack

| Component | Choice |
|-----------|--------|
| Language | Swift |
| UI | SwiftUI + Swift Charts |
| IDE | VS Code (primary) + Xcode (build/sign) |
| Database | SQLite + GRDB |
| AI | On-device analysis + optional local Ollama |
| Distribution | Xcode Archive + Notarization + DMG |

## Repository layout

```
diskwise-macos/
├── app/                    # SwiftUI desktop app
├── website/                # Next.js marketing site
├── Sources/                # Swift packages (kits)
│   ├── DatabaseKit/
│   ├── DiskScannerKit/
│   ├── MetadataKit/
│   ├── DuplicateKit/
│   ├── CleanupKit/
│   └── AIKit/
├── Tests/
├── database/migrations/    # SQL reference schema
├── docs/
├── scripts/
└── Package.swift
```

## Core modules

- **DiskScannerKit** — crawl volumes, classify files, persist scan results
- **MetadataKit** — extract video/image/archive metadata via AVFoundation and ImageIO
- **DuplicateKit** — filename, size, SHA256, and video fingerprint duplicate detection
- **CleanupKit** — preview cleanup and move files to Trash via `FileManager.trashItem`
- **AIKit** — storage insights, recommendations, optional Ollama report generation
- **DatabaseKit** — GRDB schema, migrations, repositories

## Development

### Prerequisites

- macOS 14+
- Xcode 15+ (`xcode-select --install`)
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

### Development (VS Code / terminal)

```bash
npm run info    # colored starter guide
npm run dev:app     # build, test, build app, launch on macOS
```

Package-only (without launching the app):

```bash
npm run build
npm run test
```

### Build or debug in Xcode

```bash
npm run setup:xcodegen   # once, if needed
npm run xcode            # build app + open Xcode
npm run run:app          # launch DiskWise.app only
```

If `xcodebuild` fails on a fresh Xcode install, run once:

```bash
npm run setup:xcode
npm run build:app
```

Or step by step:

```bash
npm run build:app
npm run open:xcode
```

`build:app` generates the Xcode project (via XcodeGen) and builds `DiskWise.app`.

## Workflow

1. **Scan** internal or external volumes (`/Volumes/Media01`, etc.)
2. **Detect duplicates** at four levels: filename, size, hash, video fingerprint
3. **Review AI recommendations** for duplicates, previews, and stale files
4. **Preview cleanup** and move selected files to Trash

## Roadmap

| Phase | Scope |
|-------|--------|
| **Phase 1** | Disk scanning, folder analysis, duplicate detection, cleanup |
| **Phase 2** | AI recommendations, large media analysis, duplicate videos |
| **Phase 3** | Storage trends, scheduled scans, NAS/SMB/Synology support |
| **Phase 4** | Local LLM integration (Ollama / LM Studio) |

## Documentation

- [Architecture](docs/architecture.md)
- [Database schema](docs/database.md)
- [Local development](docs/local-development.md)
- [Website](docs/website.md)

## License

Private project — all rights reserved.
