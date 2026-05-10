# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project structure

```
Meta enricher/
├── macOS/      ← Native macOS app (Swift/SwiftUI), primary version
├── Windows/    ← WinUI 3 / Windows App SDK app, single-project MSIX
```

---

## macOS app (`macOS/MetaEnricher/`)

Built with Swift + SwiftUI using `@Observable`. Targets macOS 26+. No external dependencies — uses only system frameworks (SwiftUI, ImageIO, UniformTypeIdentifiers).

### Commands

```bash
open macOS/MetaEnricher/MetaEnricher.xcodeproj   # Open in Xcode
# ⌘R — Build and run
# ⌘U — Run tests (unit + UI)
# ⌘B — Build only
```

**Prerequisites:**
```bash
ollama serve                    # Ollama must be running locally
ollama pull qwen2.5vl           # Pull the default vision model
```

### Architecture

| Layer | Files | Purpose |
|-------|-------|---------|
| App entry | `App.swift` | Routes between `OnboardingView` and `ContentView` based on `hasCompletedOnboarding` |
| State | `Models/AppState.swift` | Single `@Observable` source of truth; holds sessions, photos, UI state, settings |
| Models | `Models/Photo.swift` | `Photo` and `PhotoSession` value types |
| Services | `Services/` | Stateless actors/classes: `PhotoScanner`, `OllamaService`, `ExifService`, `GeocodingService`, `ImportService`, `ThumbnailService` |
| Views | `Views/` | SwiftUI views; inject `AppState` via `@Environment` |

**Sandbox & file access**: The app is sandboxed (`com.apple.security.app-sandbox`). User-selected folders are persisted via security-scoped bookmarks (`AppState.saveBookmark` / `restoreBookmark`) — never plain paths.

**AI enrichment flow**: `OllamaService` resizes photo (max 1280px) → base64 JPEG (85%) → POST to Ollama `/api/generate` with JSON format → `ExifService` writes IPTC/XMP/TIFF tags via native `CGImageMetadata` (lossless). Location priority: embedded GPS → reverse geocode (Nominatim) → AI guess.

**Metadata tags written** (via `ExifService.writeMeta`):
- IPTC: ObjectName, CaptionAbstract, Keywords, City, CountryPrimaryLocationName, Byline, Copyright
- XMP DC: title, description, subject, creator, rights
- TIFF: Artist, Copyright, Orientation
- GPS: Latitude/Longitude with N/S/E/W refs

**Onboarding**: Multi-step wizard in `OnboardingView`. Supports two library schemas — `metaEnricher` (fixed subfolder names) and `custom` (user-defined subfolder name).

### Photo library structure (metaEnricher schema)

```
CAMERA_ROOT/
  <year>/
    <date> [label]/    ← "session"
      Edited export/   ← edited JPEGs (what the UI browses)
      JPEG/
      RAW/
```

### Configuration

All settings via UI + UserDefaults (no env vars):

| Setting | Default | UserDefaults key |
|---------|---------|------------------|
| Ollama URL | `http://localhost:11434` | `ollamaURL` |
| Ollama Model | `qwen2.5vl` | `ollamaModel` |
| Camera root | _(user selects)_ | `cameraRootBookmark` (security-scoped) |

### Troubleshooting

- **Ollama not connecting**: Check `ollama serve` is running. App uses `com.apple.security.network.client` entitlement for localhost access. Timeout: 120s request, 300s resource.
- **EXIF write fails**: `ExifService` writes to temp file then atomic replace via `FileManager.replaceItemAt()`. If folder is read-only, the write will fail silently. Check folder permissions.
- **Sandbox bookmark stale**: If camera root stops working after macOS update, re-select the folder via Settings. Stale bookmarks are auto-detected on resolve.
- **exiftool fallback**: Batch metadata reads use exiftool at `/opt/homebrew/bin/exiftool` or `/usr/local/bin/exiftool`. Install via `brew install exiftool` if missing.

---

## Windows app (`Windows/MetaEnricher/`)

Built with C# + WinUI 3 / Windows App SDK 1.6, .NET 9, single-project MSIX (no separate `.wapproj`). Targets Windows 10 1809+ (`TargetPlatformMinVersion 10.0.17763.0`). x64 + ARM64.

### Build

- **Debug** (`Configuration=Debug`): unpackaged self-contained `.exe` for fast iteration. F5 in Visual Studio works.
- **Release / Store**: self-contained MSIX bundle with .NET 9 runtime baked in. Microsoft Store has no framework package for .NET Desktop Runtime, so framework-dependent builds crash at launch on cert lab machines.

  Build via `Windows\build-msix.ps1` (dotnet publish for both archs → `makeappx bundle` → zip to `.msixupload`). The VS "Create App Packages" wizard is unreliable for self-contained single-project MSIX (fails with `0x80080203` missing AppxManifest.xml).

### Configuration knobs in `MetaEnricher.csproj`

- `SelfContained` / `WindowsAppSDKSelfContained` — `true` for Release.
- `WindowsPackageType` — `None` for Debug (unpackaged), default MSIX for Release.
- `EnableMsixTooling` — unconditionally `true`.
- `IncludeAppxManifestInPublish` MSBuild target — copies `Package.appxmanifest` → `AppxManifest.xml` into publish output so MakeAppx finds it.

### CI

`.github/workflows/release.yml` builds two artifacts on tag `v*`:
1. Portable single-file `.exe` (`-p:WindowsPackageType=None`, single-file).
2. Store-ready `.msixbundle` + `.msixupload` (via `build-msix.ps1`).

Manifest version is overwritten from the git tag (`v1.2.3` → `1.2.3.0`). Optional code signing via `WINDOWS_CERT` / `WINDOWS_CERT_PASSWORD` secrets.

### exiftool

`exiftool.exe` + `exiftool_files\` must sit next to `MetaEnricher.csproj`. CI downloads them automatically; locally, grab the standalone build from https://exiftool.org and drop them in.
