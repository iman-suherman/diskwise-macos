# Local Development

## Prerequisites

- macOS 14+
- Xcode 15+ with command line tools
- Optional: XcodeGen (`brew install xcodegen`)
- Optional: create-dmg (`brew install create-dmg`) for DMG packaging
- Optional: Ollama for Phase 4 LLM reports

## Quick start

```bash
# Build, test packages, build app, launch on macOS
npm run dev

# One-time setup
npm run setup:xcodegen
```

Debug with breakpoints in Xcode:

```bash
npm run xcode
```

## VS Code setup

Recommended extensions:

- Swift (swiftlang.swift-vscode)
- CodeLLDB
- SourceKit-LSP (bundled with Swift extension)

You still need Xcode installed for the Swift compiler, macOS SDK, signing, and notarization.

## Scanning external drives

1. Launch DiskWise
2. Open the **Scan** tab
3. Browse to `/Volumes/<DriveName>` or paste the mount path
4. Start scan

For protected paths, grant **Full Disk Access** in System Settings → Privacy & Security.

## Ollama integration (optional)

With Ollama running locally:

```bash
ollama serve
ollama pull llama3.1
```

Use the **AI** tab → **Generate Report**. The app calls `http://127.0.0.1:11434/api/generate` by default.

## Release build

Uses the same **Huge Shop Pty Ltd** Developer ID and **`AC_NOTARY`** keychain profile as `officeless-ai-vscode-guardrail-kit`.

```bash
cp .env.release.example .env.release
npm run release
```

This builds a release `.app`, signs with `Developer ID Application: Huge Shop Pty Ltd (Q3TXW887NM)`, notarizes the DMG via `AC_NOTARY`, and outputs `DiskWise.dmg`.

If you already set up notarization in the officeless kit, the `AC_NOTARY` profile in Keychain is reused — no extra setup needed.

For a local unsigned DMG (no notarization):

```bash
npm run start
```
