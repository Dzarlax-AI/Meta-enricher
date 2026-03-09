import { exiftool } from "exiftool-vendored";
import type { GpsCoords } from "./location";

export interface PhotoMeta {
  title?: string;
  description?: string;
  keywords?: string[];
  location?: string;
  locationSource?: "gps" | "ai";
  dateTimeOriginal?: string;
  make?: string;
  model?: string;
  focalLength?: string;
  aperture?: string;
  shutterSpeed?: string;
  iso?: number;
  gps?: GpsCoords;
  rating?: number;
  creator?: string;
  copyright?: string;
}

export async function readMeta(filePath: string): Promise<PhotoMeta> {
  const tags = await exiftool.read(filePath);
  const raw = tags as Record<string, unknown>;

  // GPS coords
  let gps: GpsCoords | undefined;
  if (tags.GPSLatitude != null && tags.GPSLongitude != null) {
    gps = {
      lat: tags.GPSLatitude as number,
      lon: tags.GPSLongitude as number,
    };
  }

  // Existing location string (City + Country if written before)
  const city = (raw["City"] || raw["XMP-photoshop:City"]) as string | undefined;
  const country = (raw["Country"] || raw["XMP-photoshop:Country"] || raw["Country-PrimaryLocationName"]) as string | undefined;
  const locationParts = [city, country].filter(Boolean);
  const location = locationParts.length ? locationParts.join(", ") : undefined;

  const ratingRaw = raw["Rating"] ?? raw["XMP-xmp:Rating"];
  const rating = typeof ratingRaw === "number" ? ratingRaw : undefined;

  return {
    title: tags.Title as string | undefined,
    description: (tags.Description || raw["Caption"]) as string | undefined,
    keywords: Array.isArray(tags.Keywords)
      ? (tags.Keywords as string[])
      : tags.Keywords
      ? [tags.Keywords as string]
      : [],
    location,
    dateTimeOriginal: tags.DateTimeOriginal?.toString(),
    make: tags.Make as string | undefined,
    model: tags.Model as string | undefined,
    focalLength: tags.FocalLength?.toString(),
    aperture: tags.FNumber?.toString(),
    shutterSpeed: tags.ExposureTime?.toString(),
    iso: tags.ISO as number | undefined,
    gps,
    rating,
    creator: (raw["Creator"] || raw["Artist"] || raw["XMP-dc:Creator"]) as string | undefined,
    copyright: (raw["Copyright"] || raw["CopyrightNotice"]) as string | undefined,
  };
}

export async function writeMeta(
  filePath: string,
  meta: {
    title?: string;
    description?: string;
    keywords?: string[];
    city?: string;
    state?: string;
    country?: string;
    rating?: number;
    creator?: string;
    copyright?: string;
  }
): Promise<void> {
  const tagsToWrite: Record<string, unknown> = {};

  if (meta.title !== undefined) {
    tagsToWrite["Title"] = meta.title;
    tagsToWrite["XPTitle"] = meta.title;
  }
  if (meta.description !== undefined) {
    tagsToWrite["Description"] = meta.description;
    tagsToWrite["Caption-Abstract"] = meta.description;
    tagsToWrite["XPComment"] = meta.description;
  }
  if (meta.keywords !== undefined) {
    // Deduplicate, preserving order
    const unique = [...new Set(meta.keywords.map(k => k.trim()).filter(Boolean))];
    // Clear IPTC list tags first (exiftool appends by default),
    // then write new values in a second pass
    await exiftool.write(filePath, {}, [
      "-IPTC:Keywords=",
      "-XMP-dc:Subject=",
      "-XPKeywords=",
      "-overwrite_original",
    ]);
    if (unique.length > 0) {
      tagsToWrite["Keywords"] = unique;
      tagsToWrite["Subject"] = unique;
      tagsToWrite["XPKeywords"] = unique.join(";");
    }
  }
  if (meta.city) {
    tagsToWrite["City"] = meta.city;
    tagsToWrite["XMP-photoshop:City"] = meta.city;
  }
  if (meta.state) {
    tagsToWrite["Province-State"] = meta.state;
    tagsToWrite["XMP-photoshop:State"] = meta.state;
  }
  if (meta.country) {
    tagsToWrite["Country-PrimaryLocationName"] = meta.country;
    tagsToWrite["XMP-photoshop:Country"] = meta.country;
  }
  if (meta.rating !== undefined) {
    tagsToWrite["Rating"] = meta.rating;
  }
  if (meta.creator) {
    tagsToWrite["Creator"] = meta.creator;
    tagsToWrite["Artist"] = meta.creator;
  }
  if (meta.copyright) {
    tagsToWrite["Copyright"] = meta.copyright;
    tagsToWrite["CopyrightNotice"] = meta.copyright;
  }

  await exiftool.write(filePath, tagsToWrite, ["-overwrite_original"]);
}

export function shutdownExiftool() {
  return exiftool.end();
}
