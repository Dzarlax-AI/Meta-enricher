# MetaEnricher — App Description

**MetaEnricher** is a native application for photographers who want to automate metadata enrichment of their photo libraries using AI — available for macOS and Windows.

---

## Overview

MetaEnricher bridges the gap between shooting photos and publishing them. After a session, photographers need to add titles, descriptions, keywords, and copyright information to dozens of images. MetaEnricher automates this using a vision AI model (via Ollama), analyzing each image and generating rich, contextual metadata. You choose where the AI runs: locally on your machine for full privacy, or in the cloud for convenience.

---

## Key Features

### AI-Powered Metadata Enrichment
Connects to Ollama running a vision model (such as Qwen2.5-VL or Qwen3-VL). For each photo, the app generates a title, caption, keywords, and suggested location. Works in two modes:

- **Local mode** — Ollama runs on your own machine. Photos never leave your device.
- **Cloud mode** — Use an Ollama Cloud API key to process images on Ollama's servers. No local GPU required.

### Session-Based Workflow
Organizes your library by shooting sessions discovered automatically by date. Each session shows its edited export folder, letting you enrich only the images you intend to publish.

### Metadata Writing
Writes EXIF, IPTC, and XMP tags directly to image files for compatibility with Lightroom, Capture One, Photo Mechanic, and publishing platforms. Keywords are deduplicated, creator and copyright fields are pre-filled from your preferences.

### Smart Location Handling
GPS coordinates are reverse-geocoded to city/country names via OpenStreetMap. If no GPS data exists, the AI guesses location from visual content. Session notes let you provide context — e.g. "Shot in Tuscany" — to improve accuracy.

### Bulk Enrichment & SD Card Import
Select one photo or many for batch processing. The built-in importer scans for DCIM folders and organizes files into the correct library structure ready for enrichment.

### Privacy Options
Choose what works for you. Local mode keeps all AI inference on your device with no internet required after setup. Cloud mode requires an Ollama Cloud account but works on any machine without a dedicated GPU.

---

## Who It's For

Independent photographers and content creators who manage local photo archives and want a fast, AI-assisted way to prepare images for publication — without subscriptions or repetitive manual work.

---

## Platforms

- **macOS** — requires macOS 26 or later
- **Windows** — requires Windows 10 (1809) or later

*Requires Ollama (local install or cloud account) with a compatible vision model.*
