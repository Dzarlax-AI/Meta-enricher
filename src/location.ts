export interface GpsCoords {
  lat: number;
  lon: number;
}

export interface LocationInfo {
  city?: string;
  state?: string;
  country?: string;
  display: string;       // "Prague, Czech Republic"
  source: "gps" | "ai";
}

export async function reverseGeocode(coords: GpsCoords): Promise<LocationInfo | null> {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${coords.lat}&lon=${coords.lon}&format=json&zoom=12`;
    const res = await fetch(url, {
      headers: { "User-Agent": "MetaEnricher/1.0" },
    });
    if (!res.ok) return null;

    const data = (await res.json()) as {
      address?: {
        city?: string;
        town?: string;
        village?: string;
        municipality?: string;
        state?: string;
        country?: string;
      };
    };

    const addr = data.address;
    if (!addr) return null;

    const city = addr.city || addr.town || addr.village || addr.municipality;
    const country = addr.country;
    const state = addr.state;

    const parts = [city, country].filter(Boolean);
    if (!parts.length) return null;

    return {
      city,
      state,
      country,
      display: parts.join(", "),
      source: "gps",
    };
  } catch {
    return null;
  }
}
