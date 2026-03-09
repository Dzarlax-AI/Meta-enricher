import * as fs from "fs";
import * as os from "os";
import * as path from "path";

export interface Settings {
  ollamaUrl: string;
  ollamaModel: string;
  cameraRoot: string;
}

function defaults(): Settings {
  return {
    ollamaUrl: "http://localhost:11434",
    ollamaModel: "qwen2.5-vl",
    cameraRoot: process.platform === "win32"
      ? "D:\\Camera"
      : path.join(os.homedir(), "Pictures", "Camera"),
  };
}

function filePath(): string {
  return process.env.SETTINGS_FILE ||
    path.join(os.homedir(), ".meta-enricher", "settings.json");
}

export function getSettings(): Settings {
  try {
    return { ...defaults(), ...JSON.parse(fs.readFileSync(filePath(), "utf8")) };
  } catch {
    return defaults();
  }
}

export function saveSettings(patch: Partial<Settings>): Settings {
  const updated = { ...getSettings(), ...patch };
  const file = filePath();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(updated, null, 2), "utf8");
  return updated;
}
