"use strict";

const { app, BrowserWindow, shell, session } = require("electron");
const path = require("path");
const net = require("net");

// Prevent multiple instances — second launch focuses the existing window instead
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
  process.exit(0);
}

const isDev = !app.isPackaged;
// app.getAppPath() returns the .asar file when packaged — can't chdir into a file
const appDir = isDev ? path.join(__dirname, "..") : app.getAppPath();
const workDir = isDev ? appDir : process.resourcesPath;

// Set working directory to an actual directory (not the asar archive)
process.chdir(workDir);

// Tell the server where to find static files (works inside asar via Electron's fs patch)
process.env.APP_DIR = appDir;
process.env.CACHE_DIR = path.join(app.getPath("userData"), ".cache");
process.env.SETTINGS_FILE = path.join(app.getPath("userData"), "settings.json");

// ── Find a free port ───────────────────────────────────────────────────────────
function findFreePort(preferred) {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.listen(preferred, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
    srv.on("error", () => {
      // preferred port busy — let OS pick a free one
      const fallback = net.createServer();
      fallback.listen(0, "127.0.0.1", () => {
        const { port } = fallback.address();
        fallback.close(() => resolve(port));
      });
    });
  });
}

// ── Window ────────────────────────────────────────────────────────────────────
function createWindow(port) {
  const win = new BrowserWindow({
    width: 1400,
    height: 900,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
    title: "Meta Enricher",
  });

  win.loadURL(`http://localhost:${port}`);

  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────
app.whenReady().then(async () => {
  const preferred = parseInt(process.env.PORT || "3000", 10);
  const port = await findFreePort(preferred);
  process.env.PORT = String(port);

  if (isDev) require("tsx/cjs");
  const { serverReady, shutdownExiftool } = require(
    isDev ? "../src/server" : "../dist/server"
  );

  app.on("before-quit", async () => { await shutdownExiftool(); });

  await session.defaultSession.clearCache();
  await serverReady;
  createWindow(port);
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    const port = parseInt(process.env.PORT || "3000", 10);
    createWindow(port);
  }
});

// Focus existing window when second instance tries to launch
app.on("second-instance", () => {
  const win = BrowserWindow.getAllWindows()[0];
  if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
});
