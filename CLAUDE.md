# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev    # Run with TypeScript watch mode (development)
npm start      # Run without watch mode
```

No build step required — `tsx` handles TypeScript compilation at runtime. Output compiles to `dist/` if needed via `tsc`.

No test runner or linter is configured in this project.

## Environment Setup

Copy `.env.example` to `.env` and configure:
- `OLLAMA_URL` — Ollama API base URL (default: `http://localhost:11434`)
- `OLLAMA_MODEL` — Vision model name (e.g., `qwen2.5-vl`)
- `CAMERA_ROOT` — Absolute path to photo library root
- `PORT` — HTTP server port (default: 3000)

Requires Ollama running locally with a vision model installed.

## Architecture

Single-process Node.js HTTP server (Hono) with a plain JS frontend. No database — all state is on the filesystem.

### Module responsibilities

| File | Purpose |
|------|---------|
| `src/server.ts` | Hono HTTP server, all ~20 API routes |
| `src/photos.ts` | Session/photo discovery, path encoding |
| `src/exif.ts` | EXIF/XMP read/write via exiftool-vendored |
| `src/cache.ts` | Image resize cache (Sharp) + AI result cache |
| `src/ollama.ts` | Vision AI enrichment via local Ollama API |
| `src/location.ts` | Reverse geocoding via OSM Nominatim |
| `src/import.ts` | SD card import with async generator progress streaming |
| `public/app.js` | All frontend logic (no framework) |

### Photo library structure

```
CAMERA_ROOT/
  <year>/
    <date>/           ← "session"
      Edited export/  ← edited JPEGs; this is what the UI browses
      JPEG/           ← original JPEGs
      RAW/            ← original RAW files
```

Sessions are discovered by scanning for `Edited export` folders. The date folder can have a label suffix (e.g., `2024-07-04 Fireworks`).

### Path encoding

All file paths in API routes are Base64URL-encoded (`encodeFolderPath` / `decodeFolderPath` in `photos.ts`) to safely pass filesystem paths through HTTP URLs.

### Caching

`.cache/` holds:
- Resized image thumbnails (400px) and previews (1200px), keyed by MD5(filePath + size + mtime)
- AI enrichment JSON per photo, invalidated on file mtime change
- Session notes JSON per session

### AI enrichment flow

1. Resize photo to ≤1280px, encode as base64
2. POST to Ollama with vision prompt (title, description, keywords, location)
3. Parse JSON from response (strip markdown fences)
4. Location priority: user GPS → reverse geocode via Nominatim → AI guess
5. Cache result; invalidate on file modification

### Metadata writing

`exif.ts` writes to multiple tag targets (IPTC, XMP, legacy) for cross-tool compatibility. Keywords are deduplicated before writing. Source tracking (`"gps"` vs `"ai"`) is stored in metadata.

### Real-time updates

`GET /api/watch` is a Server-Sent Events stream that fires when the photo library folder changes (debounced 2s), used by the frontend to refresh session lists.

### SD card import

`import.ts` scans drive letters D–L for DCIM folders. Import yields progress events as NDJSON via a streaming HTTP response. Creates the full folder structure including `Edited export/` on import.
