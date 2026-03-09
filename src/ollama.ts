import * as fs from "fs";
import sharp from "sharp";
import { getSettings } from "./settings";

export interface EnrichResult {
  title: string;
  description: string;
  keywords: string[];
  location?: string;       // "Prague, Czech Republic"
  locationSource?: "gps" | "ai";
  city?: string;
  state?: string;
  country?: string;
}

function buildPrompt(locationHint?: string, notes?: string): string {
  const locationField = locationHint
    ? `  "location": "${locationHint}",  // confirmed — include in description and keywords`
    : `  "location": "City, Country or null if uncertain",  // guess from visual cues (architecture, landscape, signage, vegetation)`;

  const contextBlock = notes
    ? `\nPhotographer's notes about this photo:\n${notes}\n`
    : "";

  return `You are a professional photo metadata specialist helping photographers publish on 500px.
${contextBlock}
Analyze this photo and respond with ONLY a valid JSON object (no markdown, no explanation):
{
  "title": "Short compelling title (4-8 words, capitalize key words)",
  "description": "2-3 sentences describing subject, mood, technique, and context. Written for 500px audience.",
  "keywords": ["tag1", "tag2", ... up to 15 relevant tags in lowercase],
${locationField}
}`;
}

const MAX_SIDE = 1280; // px — enough for Qwen3-VL to understand the image

async function resizeForAI(imagePath: string): Promise<Buffer> {
  return sharp(imagePath)
    .resize(MAX_SIDE, MAX_SIDE, { fit: "inside", withoutEnlargement: true })
    .jpeg({ quality: 85 })
    .toBuffer();
}

export async function enrichPhoto(
  imagePath: string,
  locationHint?: string,
  notes?: string
): Promise<EnrichResult> {
  const imageBuffer = await resizeForAI(imagePath);
  const base64Image = imageBuffer.toString("base64");

  const { ollamaUrl, ollamaModel } = getSettings();
  const response = await fetch(`${ollamaUrl}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: ollamaModel,
      stream: false,
      messages: [
        {
          role: "user",
          content: buildPrompt(locationHint, notes),
          images: [base64Image],
        },
      ],
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Ollama error ${response.status}: ${text}`);
  }

  const data = (await response.json()) as {
    message?: { content?: string };
    error?: string;
  };

  if (data.error) throw new Error(`Ollama: ${data.error}`);

  const content = data.message?.content || "";

  // Strip markdown code fences if present
  const jsonStr = content.replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/, "").trim();

  try {
    const parsed = JSON.parse(jsonStr) as EnrichResult;
    if (!parsed.title || !parsed.description || !Array.isArray(parsed.keywords)) {
      throw new Error("Unexpected response structure");
    }

    // Normalise location
    if (locationHint) {
      parsed.location = locationHint;
      parsed.locationSource = "gps";
    } else if (parsed.location && parsed.location !== "null") {
      parsed.locationSource = "ai";
    } else {
      parsed.location = undefined;
      parsed.locationSource = undefined;
    }

    // Split "City, Country" into parts for EXIF writing
    if (parsed.location) {
      const [city, ...rest] = parsed.location.split(",").map((s) => s.trim());
      parsed.city = city;
      parsed.country = rest[rest.length - 1];
      if (rest.length > 1) parsed.state = rest[0];
    }

    return parsed;
  } catch {
    throw new Error(`Failed to parse model response: ${content}`);
  }
}

export async function checkOllama(): Promise<{ ok: boolean; models: string[] }> {
  try {
    const res = await fetch(`${getSettings().ollamaUrl}/api/tags`);
    if (!res.ok) return { ok: false, models: [] };
    const data = (await res.json()) as { models?: { name: string }[] };
    const models = (data.models || []).map((m) => m.name);
    return { ok: true, models };
  } catch {
    return { ok: false, models: [] };
  }
}
