import "dotenv/config";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { Hono } from "hono";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { getResized, getRawPreview, getAICache, setAICache, getSessionNotes, setSessionNotes } from "./cache";
import { readMeta, writeMeta, shutdownExiftool } from "./exif";
import { enrichPhoto, checkOllama } from "./ollama";
import { reverseGeocode } from "./location";
import {
  listSessions,
  listPhotos,
  listOriginals,
  encodeFolderPath,
  decodeFolderPath,
  findOriginals,
  RAW_EXTS,
} from "./photos";
import { findCardDrives, previewImport, runImport } from "./import";
import { getSettings, saveSettings } from "./settings";

const app = new Hono();

// Disable caching for static assets so CSS/JS changes are picked up immediately
app.use("/*.css", async (c, next) => { await next(); c.res.headers.set("Cache-Control", "no-cache, must-revalidate"); });
app.use("/*.js",  async (c, next) => { await next(); c.res.headers.set("Cache-Control", "no-cache, must-revalidate"); });

// Serve static files from public/
// When packaged, APP_DIR points to the asar root (Electron patches fs so it's readable)
const staticRoot = process.env.APP_DIR
  ? path.join(process.env.APP_DIR, "public")
  : path.join(process.cwd(), "public");
app.use("/*", serveStatic({ root: staticRoot }));

// ── API ──────────────────────────────────────────────────────────────────────

// Health / Ollama status
app.get("/api/status", async (c) => {
  const status = await checkOllama();
  return c.json(status);
});

// List all sessions (year/date/Edited export folders)
app.get("/api/sessions", (c) => {
  const sessions = listSessions();
  return c.json(
    sessions.map((s) => ({ ...s, folderKey: encodeFolderPath(s.folderPath) }))
  );
});

// List photos in a session
app.get("/api/photos/:folderKey", async (c) => {
  const folderPath = decodeFolderPath(c.req.param("folderKey"));
  const photos = listPhotos(folderPath);

  const result = await Promise.all(
    photos.map(async (p) => {
      const meta = await readMeta(p);
      const originals = findOriginals(p);
      return {
        fileKey: encodeFolderPath(p),
        fileName: path.basename(p),
        meta,
        originals: {
          jpeg: originals.jpeg ? encodeFolderPath(originals.jpeg) : null,
          raw:  originals.raw  ? encodeFolderPath(originals.raw)  : null,
        },
      };
    })
  );

  return c.json(result);
});

// Serve a photo — ?size=thumb (400px) | ?size=preview (1200px) | full
app.get("/api/image/:fileKey", async (c) => {
  const filePath = decodeFolderPath(c.req.param("fileKey"));
  if (!fs.existsSync(filePath)) return c.text("Not found", 404);

  const size = c.req.query("size");

  if (size === "thumb" || size === "preview") {
    const buf = await getResized(filePath, size);
    return new Response(buf as unknown as BodyInit, {
      headers: { "Content-Type": "image/jpeg", "Cache-Control": "no-store" },
    });
  }

  const ext = path.extname(filePath).toLowerCase();
  const mimeMap: Record<string, string> = {
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".png": "image/png", ".tif": "image/tiff", ".tiff": "image/tiff",
  };
  const stream = fs.createReadStream(filePath);
  return new Response(stream as unknown as ReadableStream, {
    headers: { "Content-Type": mimeMap[ext] || "application/octet-stream" },
  });
});

// Read metadata for a single photo
app.get("/api/meta/:fileKey", async (c) => {
  const filePath = decodeFolderPath(c.req.param("fileKey"));
  if (!fs.existsSync(filePath)) return c.text("Not found", 404);
  const meta = await readMeta(filePath);
  return c.json(meta);
});

// Enrich a photo with AI (returns suggestions, does NOT save)
// Body (optional): { locationHint?: string }
app.post("/api/enrich/:fileKey", async (c) => {
  const filePath = decodeFolderPath(c.req.param("fileKey"));
  if (!fs.existsSync(filePath)) return c.text("Not found", 404);

  try {
    const body = await c.req.json().catch(() => ({})) as {
      locationHint?: string;
      notes?: string;
      sessionNotes?: string;
    };

    // Priority: 1) client-provided hint, 2) GPS→geocoding, 3) nothing (AI guesses)
    let locationHint: string | undefined = body.locationHint?.trim() || undefined;

    if (!locationHint) {
      const meta = await readMeta(filePath);
      if (meta.gps) {
        const loc = await reverseGeocode(meta.gps);
        if (loc) locationHint = loc.display;
      }
    }

    // Merge per-photo notes and session-level notes
    const noteParts = [body.sessionNotes?.trim(), body.notes?.trim()].filter(Boolean);
    const notes = noteParts.length ? noteParts.join("\n") : undefined;

    // Check AI cache first (skip if locationHint overrides GPS)
    const cached = getAICache(filePath);
    if (cached && !body.locationHint && !body.notes) {
      return c.json(cached);
    }

    const result = await enrichPhoto(filePath, locationHint, notes);
    setAICache(filePath, result);
    return c.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return c.json({ error: message }, 500);
  }
});

// Save metadata to a photo
app.post("/api/save/:fileKey", async (c) => {
  const filePath = decodeFolderPath(c.req.param("fileKey"));
  if (!fs.existsSync(filePath)) return c.text("Not found", 404);

  const body = (await c.req.json()) as {
    title?: string;
    description?: string;
    keywords?: string[];
    city?: string;
    state?: string;
    country?: string;
    rating?: number;
    creator?: string;
    copyright?: string;
  };

  try {
    await writeMeta(filePath, body);
    const meta = await readMeta(filePath);
    return c.json({ ok: true, meta });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return c.json({ error: message }, 500);
  }
});

// Batch save — apply partial fields to multiple photos
// keywordsMode: "replace" | "add"
app.post("/api/batch-save", async (c) => {
  const body = (await c.req.json()) as {
    fileKeys: string[];
    city?: string;
    state?: string;
    country?: string;
    keywords?: string[];
    keywordsMode?: "replace" | "add";
  };

  const results: { fileKey: string; ok: boolean; error?: string }[] = [];

  for (const fileKey of body.fileKeys) {
    const filePath = decodeFolderPath(fileKey);
    if (!fs.existsSync(filePath)) {
      results.push({ fileKey, ok: false, error: "File not found" });
      continue;
    }
    try {
      let keywords = body.keywords;
      if (body.keywordsMode === "add" && keywords?.length) {
        const existing = await readMeta(filePath);
        const merged = [...new Set([...(existing.keywords || []), ...keywords])];
        keywords = merged;
      }
      await writeMeta(filePath, {
        city: body.city,
        state: body.state,
        country: body.country,
        keywords,
      });
      results.push({ fileKey, ok: true });
    } catch (err) {
      results.push({ fileKey, ok: false, error: err instanceof Error ? err.message : String(err) });
    }
  }

  return c.json({ results });
});

// Session notes — persisted to .cache/<session>/notes.txt
app.get("/api/session-notes/:folderKey", (c) => {
  const folderPath = decodeFolderPath(c.req.param("folderKey"));
  return c.json({ text: getSessionNotes(folderPath) });
});

app.post("/api/session-notes/:folderKey", async (c) => {
  const { text } = (await c.req.json()) as { text: string };
  const folderPath = decodeFolderPath(c.req.param("folderKey"));
  setSessionNotes(folderPath, text);
  return c.json({ ok: true });
});

// Reveal a file in the system file manager
app.post("/api/reveal/:fileKey", async (c) => {
  const filePath = decodeFolderPath(c.req.param("fileKey"));
  if (!fs.existsSync(filePath)) return c.json({ error: "Not found" }, 404);
  const { exec } = await import("child_process");
  if (process.platform === "win32") {
    exec(`explorer /select,"${filePath.replace(/\//g, "\\")}"`);
  } else if (process.platform === "darwin") {
    exec(`open -R "${filePath}"`);
  } else {
    // Linux: xdg-open opens the parent folder
    exec(`xdg-open "${path.dirname(filePath)}"`);
  }
  return c.json({ ok: true });
});

// Deduplicate keywords on one or more photos
app.post("/api/dedup-keywords", async (c) => {
  const { fileKeys } = (await c.req.json()) as { fileKeys: string[] };
  const results: { fileKey: string; ok: boolean; removed: number; error?: string }[] = [];

  for (const fileKey of fileKeys) {
    const filePath = decodeFolderPath(fileKey);
    if (!fs.existsSync(filePath)) {
      results.push({ fileKey, ok: false, removed: 0, error: "File not found" });
      continue;
    }
    try {
      const meta = await readMeta(filePath);
      const original = meta.keywords ?? [];
      const unique = [...new Set(original.map(k => k.trim()).filter(Boolean))];
      const removed = original.length - unique.length;
      if (removed > 0) {
        await writeMeta(filePath, { keywords: unique });
      }
      results.push({ fileKey, ok: true, removed });
    } catch (err) {
      results.push({ fileKey, ok: false, removed: 0, error: err instanceof Error ? err.message : String(err) });
    }
  }

  return c.json({ results });
});

// ── Originals (JPEG + RAW from import folders) ────────────────────────────────

app.get("/api/originals/:folderKey", (c) => {
  const folderPath = decodeFolderPath(c.req.param("folderKey"));
  const originals = listOriginals(folderPath);
  return c.json(originals);
});

// Serve original file — JPEG resized or RAW embedded preview
app.get("/api/image-raw/:fileKey", async (c) => {
  const filePath = decodeFolderPath(c.req.param("fileKey"));
  if (!fs.existsSync(filePath)) return c.text("Not found", 404);

  const size = c.req.query("size") as "thumb" | "preview" | undefined;
  const ext = path.extname(filePath).toLowerCase();
  const isRaw = RAW_EXTS.has(ext);

  if (size === "thumb" || size === "preview") {
    if (isRaw) {
      const buf = await getRawPreview(filePath, size);
      if (!buf) {
        // Return a minimal placeholder so the card doesn't break
        return c.text("No preview", 404);
      }
      return new Response(buf as unknown as BodyInit, {
        headers: { "Content-Type": "image/jpeg", "Cache-Control": "no-store" },
      });
    }
    const buf = await getResized(filePath, size);
    return new Response(buf as unknown as BodyInit, {
      headers: { "Content-Type": "image/jpeg", "Cache-Control": "no-store" },
    });
  }

  // Full size — for JPEG only (RAW can't be served raw to browser)
  if (!isRaw) {
    const stream = fs.createReadStream(filePath);
    return new Response(stream as unknown as ReadableStream, {
      headers: { "Content-Type": "image/jpeg" },
    });
  }
  return c.text("RAW files cannot be served directly", 415);
});

// ── Import from SD card ───────────────────────────────────────────────────────

app.get("/api/import/drives", (c) => {
  const drives = findCardDrives();
  return c.json({ drives });
});

app.get("/api/import/preview", (c) => {
  const drive = c.req.query("drive");
  if (!drive) return c.json({ error: "Missing drive parameter" }, 400);
  try {
    const preview = previewImport(drive);
    return c.json(preview);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return c.json({ error: message }, 500);
  }
});

app.post("/api/import/run", async (c) => {
  const { drive } = (await c.req.json()) as { drive: string };
  if (!drive) return c.json({ error: "Missing drive" }, 400);

  const stream = new ReadableStream({
    async start(controller) {
      const encoder = new TextEncoder();
      try {
        for await (const event of runImport(drive)) {
          controller.enqueue(encoder.encode(JSON.stringify(event) + "\n"));
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        controller.enqueue(
          encoder.encode(JSON.stringify({ type: "error", file: "", message: msg }) + "\n")
        );
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: { "Content-Type": "application/x-ndjson" },
  });
});

// ── Rename session ─────────────────────────────────────────────────────────────

app.post("/api/rename-session/:folderKey", async (c) => {
  const folderPath = decodeFolderPath(c.req.param("folderKey"));
  // folderPath ends in "\Edited export", parent is the date folder
  const editedFolderName = path.basename(folderPath);
  const dateFolderPath = path.dirname(folderPath);
  const parentDir = path.dirname(dateFolderPath);

  if (!fs.existsSync(dateFolderPath)) {
    return c.json({ error: "Session folder not found" }, 404);
  }

  const { label } = (await c.req.json()) as { label: string };
  const currentName = path.basename(dateFolderPath);

  // Extract the date part (YYYY-MM-DD)
  const dateMatch = currentName.match(/^(\d{4}-\d{2}-\d{2})/);
  if (!dateMatch) return c.json({ error: "Could not parse date from folder name" }, 400);

  const datePart = dateMatch[1];
  const newName = label.trim() ? `${datePart} ${label.trim()}` : datePart;
  const newDateFolderPath = path.join(parentDir, newName);

  if (newDateFolderPath !== dateFolderPath) {
    try {
      fs.renameSync(dateFolderPath, newDateFolderPath);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return c.json({ error: message }, 500);
    }
  }

  const newEditedPath = path.join(newDateFolderPath, editedFolderName);
  const newFolderKey = encodeFolderPath(newEditedPath);
  return c.json({ ok: true, folderKey: newFolderKey });
});

// ── Settings ──────────────────────────────────────────────────────────────────

app.get("/api/settings", (c) => {
  return c.json(getSettings());
});

app.post("/api/settings", async (c) => {
  const patch = await c.req.json();
  const updated = saveSettings(patch);
  return c.json(updated);
});

// Open system folder picker (Electron only)
app.get("/api/pick-folder", async (c) => {
  try {
    const { dialog } = require("electron") as typeof import("electron");
    const result = await dialog.showOpenDialog({ properties: ["openDirectory"] });
    if (result.canceled) return c.json({ path: null });
    return c.json({ path: result.filePaths[0] });
  } catch {
    return c.json({ path: null });
  }
});

// ── Watch folder (SSE) ────────────────────────────────────────────────────────

app.get("/api/watch", (c) => {
  const root = getSettings().cameraRoot;
  if (!fs.existsSync(root)) {
    return new Response("data: {\"event\":\"unavailable\"}\n\n", {
      headers: { "Content-Type": "text/event-stream" },
    });
  }

  let watcher: fs.FSWatcher | null = null;
  let keepaliveTimer: ReturnType<typeof setInterval> | null = null;
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    start(controller) {
      const send = (data: object) => {
        try { controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`)); } catch { /* client gone */ }
      };
      try {
        watcher = fs.watch(root, { recursive: true }, (_event, filename) => {
          if (!filename) return;
          if (debounceTimer) clearTimeout(debounceTimer);
          debounceTimer = setTimeout(() => send({ event: "change" }), 2000);
        });
      } catch { /* fs.watch unavailable on this path */ }
      keepaliveTimer = setInterval(() => send({ event: "ping" }), 25000);
    },
    cancel() {
      watcher?.close();
      if (keepaliveTimer) clearInterval(keepaliveTimer);
      if (debounceTimer) clearTimeout(debounceTimer);
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
    },
  });
});

// ── Start ────────────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT || "3000", 10);

export const serverReady = new Promise<void>((resolve) => {
  serve({ fetch: app.fetch, port: PORT }, () => {
    console.log(`Meta Enricher running at http://localhost:${PORT}`);
    resolve();
  });
});

export { shutdownExiftool };

process.on("SIGINT", async () => {
  await shutdownExiftool();
  process.exit(0);
});
