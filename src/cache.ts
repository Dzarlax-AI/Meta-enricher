import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import { spawn } from "child_process";
import sharp from "sharp";

// Resolve exiftool binary path from the vendored package (exports the path string directly)
let EXIFTOOL_BIN = "exiftool";
try {
  const vendored = process.platform === "win32"
    ? require("exiftool-vendored.exe")
    : require("exiftool-vendored.pl");
  EXIFTOOL_BIN = typeof vendored === "string" ? vendored : (vendored.exiftoolPath ?? vendored);
} catch { /* fall back to PATH */ }

const CACHE_DIR = process.env.CACHE_DIR || path.join(process.cwd(), ".cache");

if (!fs.existsSync(CACHE_DIR)) {
  fs.mkdirSync(CACHE_DIR, { recursive: true });
}

// Human-readable folder name from a session path
// e.g. D:\Camera\2026\2026-03-07\Edited export → Camera_2026_2026-03-07_Edited_export
function sessionDirName(sessionPath: string): string {
  return sessionPath
    .replace(/^[A-Za-z]:[/\\]/i, "")      // strip drive letter
    .replace(/[/\\]+/g, "_")               // separators → _
    .replace(/\s+/g, "_")                  // spaces → _
    .replace(/[^a-zA-Z0-9_-]/g, "");       // strip remaining special chars
}

function sessionCacheDir(sessionPath: string): string {
  return path.join(CACHE_DIR, sessionDirName(sessionPath));
}

function ensureDir(dir: string): string {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return dir;
}

// ── Image cache ───────────────────────────────────────────────────────────────

const CACHE_VERSION = "v2"; // bump to invalidate all cached images

export async function getResized(
  filePath: string,
  size: "thumb" | "preview"
): Promise<Buffer> {
  const mtime = fs.statSync(filePath).mtimeMs;
  const key = crypto
    .createHash("md5")
    .update(`${filePath}|${size}|${mtime}|${CACHE_VERSION}`)
    .digest("hex");

  const sessionDir = path.dirname(filePath);
  const subdir = size === "thumb" ? "thumbs" : "previews";
  const cacheDir = ensureDir(path.join(sessionCacheDir(sessionDir), subdir));
  const cachePath = path.join(cacheDir, `${key}.jpg`);

  if (fs.existsSync(cachePath)) {
    return fs.readFileSync(cachePath);
  }

  const maxPx = size === "thumb" ? 400 : 1200;
  const quality = size === "thumb" ? 75 : 88;

  const buf = await sharp(filePath)
    .rotate()
    .resize(maxPx, maxPx, { fit: "inside", withoutEnlargement: true })
    .jpeg({ quality })
    .toBuffer();

  fs.writeFileSync(cachePath, buf);
  return buf;
}

// ── AI response cache ─────────────────────────────────────────────────────────

export interface AICacheEntry {
  mtime: number;
  result: unknown;
}

export function getAICache(filePath: string): unknown | null {
  const cacheDir = path.join(sessionCacheDir(path.dirname(filePath)), "ai");
  const cachePath = path.join(cacheDir, `${path.basename(filePath)}.json`);
  if (!fs.existsSync(cachePath)) return null;
  try {
    const entry: AICacheEntry = JSON.parse(fs.readFileSync(cachePath, "utf8"));
    const mtime = fs.statSync(filePath).mtimeMs;
    if (entry.mtime !== mtime) return null; // file changed → invalidate
    return entry.result;
  } catch {
    return null;
  }
}

export function setAICache(filePath: string, result: unknown): void {
  const cacheDir = ensureDir(path.join(sessionCacheDir(path.dirname(filePath)), "ai"));
  const cachePath = path.join(cacheDir, `${path.basename(filePath)}.json`);
  const mtime = fs.statSync(filePath).mtimeMs;
  fs.writeFileSync(cachePath, JSON.stringify({ mtime, result }, null, 2), "utf8");
}

// ── Session notes ─────────────────────────────────────────────────────────────

export function getSessionNotes(folderPath: string): string {
  const newPath = path.join(sessionCacheDir(folderPath), "notes.txt");
  if (fs.existsSync(newPath)) return fs.readFileSync(newPath, "utf8");

  // Migrate from old flat format: session-notes-<base64url>.txt
  const oldKey = Buffer.from(folderPath).toString("base64url");
  const oldPath = path.join(CACHE_DIR, `session-notes-${oldKey}.txt`);
  if (fs.existsSync(oldPath)) {
    const text = fs.readFileSync(oldPath, "utf8");
    setSessionNotes(folderPath, text);
    try { fs.unlinkSync(oldPath); } catch { /* ignore */ }
    return text;
  }

  return "";
}

export function setSessionNotes(folderPath: string, text: string): void {
  const dir = ensureDir(sessionCacheDir(folderPath));
  fs.writeFileSync(path.join(dir, "notes.txt"), text ?? "", "utf8");
}

// ── RAW embedded preview ──────────────────────────────────────────────────────

/** Extract embedded JPEG from a RAW file via exiftool. Returns null if none found. */
async function extractRawEmbeddedJpeg(filePath: string): Promise<Buffer | null> {
  for (const tag of ["-JpgFromRaw", "-PreviewImage"]) {
    const buf = await new Promise<Buffer | null>((resolve) => {
      const chunks: Buffer[] = [];
      const proc = spawn(EXIFTOOL_BIN, ["-b", tag, filePath]);
      proc.stdout.on("data", (chunk: Buffer) => chunks.push(chunk));
      proc.on("close", () => {
        const result = Buffer.concat(chunks);
        resolve(result.length > 1000 ? result : null);
      });
      proc.on("error", () => resolve(null));
    });
    if (buf) return buf;
  }
  return null;
}

export async function getRawPreview(
  filePath: string,
  size: "thumb" | "preview"
): Promise<Buffer | null> {
  const mtime = fs.statSync(filePath).mtimeMs;
  const key = crypto
    .createHash("md5")
    .update(`${filePath}|raw|${size}|${mtime}|${CACHE_VERSION}`)
    .digest("hex");

  const sessionDir = path.dirname(filePath);
  const subdir = size === "thumb" ? "raw-thumbs" : "raw-previews";
  const cacheDir = ensureDir(path.join(sessionCacheDir(sessionDir), subdir));
  const cachePath = path.join(cacheDir, `${key}.jpg`);

  if (fs.existsSync(cachePath)) return fs.readFileSync(cachePath);

  const rawBuf = await extractRawEmbeddedJpeg(filePath);
  if (!rawBuf) return null;

  const maxPx = size === "thumb" ? 400 : 1200;
  const quality = size === "thumb" ? 75 : 88;

  try {
    const buf = await sharp(rawBuf)
      .rotate()
      .resize(maxPx, maxPx, { fit: "inside", withoutEnlargement: true })
      .jpeg({ quality })
      .toBuffer();
    fs.writeFileSync(cachePath, buf);
    return buf;
  } catch {
    return null;
  }
}
