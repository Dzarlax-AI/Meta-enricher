import * as fs from "fs";
import * as path from "path";
import { getSettings } from "./settings";
const EDITED_FOLDER = "Edited export";
const IMAGE_EXTS = new Set([".jpg", ".jpeg", ".png", ".tif", ".tiff"]);
export const RAW_EXTS = new Set([".arw", ".nef", ".cr2", ".cr3", ".orf", ".rw2", ".dng", ".raf", ".pef", ".srw", ".x3f"]);

export interface Originals {
  jpeg?: string;
  raw?: string;
}

export function findOriginals(editedFilePath: string): Originals {
  // editedFilePath: .../Edited export/DSC08824.jpg
  // originals: .../<date>/JPEG/DSC08824.JPG  and  .../<date>/RAW/DSC08824.ARW
  const dateDir = path.dirname(path.dirname(editedFilePath));
  const base = path.basename(editedFilePath, path.extname(editedFilePath));

  const result: Originals = {};

  // Look for JPEG original — folder name may vary in case on different systems
  for (const jpegDir of ["JPEG", "Jpeg", "jpeg", "JPG", "jpg"]) {
    for (const ext of [".JPG", ".jpg", ".JPEG", ".jpeg"]) {
      const p = path.join(dateDir, jpegDir, base + ext);
      if (fs.existsSync(p)) { result.jpeg = p; break; }
    }
    if (result.jpeg) break;
  }

  // Look for RAW original
  for (const rawDir of ["RAW", "Raw", "raw"]) {
    const dir = path.join(dateDir, rawDir);
    if (!fs.existsSync(dir)) continue;
    for (const ext of RAW_EXTS) {
      const p = path.join(dir, base + ext);
      if (fs.existsSync(p)) { result.raw = p; break; }
      const pUp = path.join(dir, base + ext.toUpperCase());
      if (fs.existsSync(pUp)) { result.raw = pUp; break; }
    }
    if (result.raw) break;
  }

  return result;
}

export interface PhotoSession {
  year: string;
  date: string;
  label: string;
  folderPath: string;
  photoCount: number;
}

export function listSessions(): PhotoSession[] {
  const sessions: PhotoSession[] = [];
  const cameraRoot = getSettings().cameraRoot;

  if (!fs.existsSync(cameraRoot)) return sessions;

  const years = fs
    .readdirSync(cameraRoot, { withFileTypes: true })
    .filter((e) => e.isDirectory() && /^\d{4}$/.test(e.name))
    .map((e) => e.name)
    .sort()
    .reverse();

  for (const year of years) {
    const yearPath = path.join(cameraRoot, year);
    const dateFolders = fs
      .readdirSync(yearPath, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort()
      .reverse();

    for (const dateFolder of dateFolders) {
      const editedPath = path.join(yearPath, dateFolder, EDITED_FOLDER);
      if (!fs.existsSync(editedPath)) continue;

      const photos = fs
        .readdirSync(editedPath)
        .filter((f) => IMAGE_EXTS.has(path.extname(f).toLowerCase()));

      // Extract label (part after date like "2026-03-07 Prague" → "Prague")
      const labelMatch = dateFolder.match(/^\d{4}-\d{2}-\d{2}\s*(.*)$/);
      const label = labelMatch?.[1]?.trim() ?? "";

      sessions.push({
        year,
        date: dateFolder,
        label,
        folderPath: editedPath,
        photoCount: photos.length,
      });
    }
  }

  return sessions;
}

export function listPhotos(folderPath: string): string[] {
  if (!fs.existsSync(folderPath)) return [];
  return fs
    .readdirSync(folderPath)
    .filter((f) => !f.startsWith("._") && IMAGE_EXTS.has(path.extname(f).toLowerCase()))
    .map((f) => path.join(folderPath, f));
}

export function encodeFolderPath(folderPath: string): string {
  return Buffer.from(folderPath).toString("base64url");
}

export function decodeFolderPath(encoded: string): string {
  return Buffer.from(encoded, "base64url").toString();
}

export interface OriginalShot {
  base: string;           // filename without extension, e.g. "DSC08824"
  jpegKey?: string;       // fileKey for JPEG original
  rawKey?: string;        // fileKey for RAW original
  jpegName?: string;
  rawName?: string;
}

export function listOriginals(sessionFolderPath: string): OriginalShot[] {
  // sessionFolderPath is "Edited export"; originals live in sibling JPEG/ and RAW/
  const dateDir = path.dirname(sessionFolderPath);
  const byBase = new Map<string, OriginalShot>();

  // JPEG originals
  for (const jpegDir of ["JPEG", "Jpeg", "jpeg", "JPG", "jpg"]) {
    const dir = path.join(dateDir, jpegDir);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (f.startsWith("._")) continue;
      const ext = path.extname(f).toLowerCase();
      if (ext !== ".jpg" && ext !== ".jpeg") continue;
      const base = path.basename(f, path.extname(f)).toUpperCase();
      const entry = byBase.get(base) ?? { base };
      entry.jpegKey = encodeFolderPath(path.join(dir, f));
      entry.jpegName = f;
      byBase.set(base, entry);
    }
    break;
  }

  // RAW originals
  for (const rawDir of ["RAW", "Raw", "raw"]) {
    const dir = path.join(dateDir, rawDir);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (f.startsWith("._")) continue;
      if (!RAW_EXTS.has(path.extname(f).toLowerCase())) continue;
      const base = path.basename(f, path.extname(f)).toUpperCase();
      const entry = byBase.get(base) ?? { base };
      entry.rawKey = encodeFolderPath(path.join(dir, f));
      entry.rawName = f;
      byBase.set(base, entry);
    }
    break;
  }

  return [...byBase.values()].sort((a, b) => a.base.localeCompare(b.base));
}
