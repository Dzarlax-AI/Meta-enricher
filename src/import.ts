import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { exiftool } from "exiftool-vendored";
import { getSettings } from "./settings";
const SCAN_EXTS = new Set([".arw", ".jpg", ".jpeg"]);

// ── Drive scan ────────────────────────────────────────────────────────────────

function hasDcim(mountPoint: string): boolean {
  try {
    const dcim = path.join(mountPoint, "DCIM");
    return fs.existsSync(dcim) && fs.statSync(dcim).isDirectory();
  } catch {
    return false;
  }
}

export function findCardDrives(): string[] {
  if (process.platform === "win32") {
    const drives: string[] = [];
    for (let code = "D".charCodeAt(0); code <= "L".charCodeAt(0); code++) {
      const letter = String.fromCharCode(code);
      const drive = `${letter}:`;
      if (hasDcim(drive + "\\")) drives.push(drive);
    }
    return drives;
  }

  if (process.platform === "darwin") {
    try {
      return fs.readdirSync("/Volumes")
        .map((name) => path.join("/Volumes", name))
        .filter((mount) => hasDcim(mount));
    } catch {
      return [];
    }
  }

  // Linux: /media/<user>/* and /run/media/<user>/*
  const roots = [
    path.join("/media", os.userInfo().username),
    path.join("/run/media", os.userInfo().username),
  ];
  const drives: string[] = [];
  for (const root of roots) {
    try {
      for (const name of fs.readdirSync(root)) {
        const mount = path.join(root, name);
        if (hasDcim(mount)) drives.push(mount);
      }
    } catch {
      // root doesn't exist — skip
    }
  }
  return drives;
}

// ── Recursive file scan ───────────────────────────────────────────────────────

function scanDcim(drive: string): string[] {
  // On Windows "D:" + "DCIM" = "D:DCIM" (wrong) — ensure trailing separator
  const root = drive.endsWith(path.sep) ? drive : drive + path.sep;
  const dcim = path.join(root, "DCIM");
  const files: string[] = [];

  function walk(dir: string) {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        walk(full);
      } else if (e.isFile()) {
        if (!e.name.startsWith("._") && SCAN_EXTS.has(path.extname(e.name).toLowerCase())) {
          files.push(full);
        }
      }
    }
  }

  walk(dcim);
  return files;
}

function dateFromMtime(filePath: string): string {
  const mtime = fs.statSync(filePath).mtime;
  const y = mtime.getFullYear();
  const m = String(mtime.getMonth() + 1).padStart(2, "0");
  const d = String(mtime.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

async function dateFromExif(filePath: string): Promise<string> {
  try {
    const tags = await exiftool.read(filePath);
    const dto = tags.DateTimeOriginal?.toString();
    if (dto) {
      const match = dto.match(/^(\d{4}):(\d{2}):(\d{2})/);
      if (match) return `${match[1]}-${match[2]}-${match[3]}`;
    }
  } catch { /* fall through */ }
  return dateFromMtime(filePath);
}

function destPathFor(srcPath: string): string {
  const date = dateFromMtime(srcPath);
  const year = date.slice(0, 4);
  const ext = path.extname(srcPath).toLowerCase();
  const subFolder = ext === ".arw" ? "RAW" : "JPEG";
  return path.join(getSettings().cameraRoot, year, date, subFolder, path.basename(srcPath));
}

// ── Preview ───────────────────────────────────────────────────────────────────

export interface ImportPreview {
  total: number;
  newCount: number;
  existingCount: number;
  dates: string[];
}

export function previewImport(drive: string): ImportPreview {
  const files = scanDcim(drive);
  const newDates = new Set<string>();
  let newCount = 0;
  let existingCount = 0;

  for (const f of files) {
    const dest = destPathFor(f);
    if (fs.existsSync(dest)) {
      existingCount++;
    } else {
      newCount++;
      newDates.add(dateFromMtime(f));
    }
  }

  return {
    total: files.length,
    newCount,
    existingCount,
    dates: [...newDates].sort(),
  };
}

// ── Run import ────────────────────────────────────────────────────────────────

export interface ProgressEvent {
  type: "progress";
  done: number;
  total: number;
  file: string;
  skipped: boolean;
}

export interface DoneEvent {
  type: "done";
  copied: number;
  skippedCount: number;
}

export interface ErrorEvent {
  type: "error";
  file: string;
  message: string;
}

export type ImportEvent = ProgressEvent | DoneEvent | ErrorEvent;

export async function* runImport(drive: string): AsyncGenerator<ImportEvent> {
  const files = scanDcim(drive);
  const total = files.length;
  let done = 0;
  let copied = 0;
  let skippedCount = 0;

  // Collect unique session folders to create "Edited export" dirs
  const sessionDirs = new Set<string>();

  for (const src of files) {
    const date = await dateFromExif(src);
    const year = date.slice(0, 4);
    const ext = path.extname(src).toLowerCase();
    const subFolder = ext === ".arw" ? "RAW" : "JPEG";
    const sessionDir = path.join(getSettings().cameraRoot, year, date);
    const destDir = path.join(sessionDir, subFolder);
    const dest = path.join(destDir, path.basename(src));

    sessionDirs.add(sessionDir);

    done++;

    if (fs.existsSync(dest)) {
      skippedCount++;
      yield { type: "progress", done, total, file: path.basename(src), skipped: true };
      continue;
    }

    try {
      fs.mkdirSync(destDir, { recursive: true });
      fs.copyFileSync(src, dest);
      copied++;
      yield { type: "progress", done, total, file: path.basename(src), skipped: false };
    } catch (err) {
      yield {
        type: "error",
        file: path.basename(src),
        message: err instanceof Error ? err.message : String(err),
      };
    }
  }

  // Ensure "Edited export" folder exists for every session (so it appears in app)
  for (const sessionDir of sessionDirs) {
    const editedDir = path.join(sessionDir, "Edited export");
    try {
      fs.mkdirSync(editedDir, { recursive: true });
    } catch {
      // ignore
    }
  }

  yield { type: "done", copied, skippedCount };
}
