/** 気象庁 警報・注意報 (unofficial JSON under jma.go.jp/bosai). Server-side polling only. */
export type Warning = { areaCode: string; code: string; name: string; status: string; kind: "flood" | "heavy_rain" | "landslide" | "tsunami" | "storm_surge" | "other"; level: "special" | "warning" | "advisory" };

/** Warning codes we care about (subset). */
export const WARN_CODES: Record<string, { name: string; kind: Warning["kind"]; level: Warning["level"] }> = {
  "33": { name: "大雨特別警報", kind: "heavy_rain", level: "special" },
  "03": { name: "大雨警報", kind: "heavy_rain", level: "warning" },
  "04": { name: "洪水警報", kind: "flood", level: "warning" },
  "10": { name: "大雨注意報", kind: "heavy_rain", level: "advisory" },
  "18": { name: "洪水注意報", kind: "flood", level: "advisory" },
  "35": { name: "高潮特別警報", kind: "storm_surge", level: "special" },
  "08": { name: "高潮警報", kind: "storm_surge", level: "warning" },
  "37": { name: "大津波警報", kind: "tsunami", level: "special" },
  "36": { name: "津波警報", kind: "tsunami", level: "warning" },
  "07": { name: "津波注意報", kind: "tsunami", level: "advisory" },
};

/** All active warnings nationwide, keyed by class20 (7-digit municipality) code. */
export async function fetchWarningsMap(): Promise<Warning[]> {
  const r = await fetch("https://www.jma.go.jp/bosai/warning/data/warning/map.json", { headers: { "User-Agent": "hinamichi/0.1" } });
  if (!r.ok) throw new Error(`jma map.json ${r.status}`);
  const reports: any[] = await r.json();
  const out: Warning[] = [];
  for (const rep of reports) {
    const types = rep?.areaTypes ?? [];
    const muni = types[1]?.areas ?? types[types.length - 1]?.areas ?? [];
    for (const a of muni) {
      for (const w of a.warnings ?? []) {
        const def = WARN_CODES[String(w.code)];
        if (!def || !w.code) continue;
        if (w.status === "解除") continue;
        out.push({ areaCode: String(a.code), code: String(w.code), name: def.name, status: w.status, kind: def.kind, level: def.level });
      }
    }
  }
  return out;
}

/** Warnings for one municipality (class20 code). Uses the prefecture office file, which includes levels. */
export async function fetchWarningsFor(office: string, class20: string): Promise<Warning[]> {
  const r = await fetch(`https://www.jma.go.jp/bosai/warning/data/warning/${office}.json`, { headers: { "User-Agent": "hinamichi/0.1" } });
  if (!r.ok) return [];
  const j: any = await r.json();
  const out: Warning[] = [];
  for (const t of j?.areaTypes ?? []) {
    for (const a of t.areas ?? []) {
      if (String(a.code) !== class20) continue;
      for (const w of a.warnings ?? []) {
        const def = WARN_CODES[String(w.code)];
        if (!def || w.status === "解除") continue;
        out.push({ areaCode: class20, code: String(w.code), name: def.name, status: w.status, kind: def.kind, level: def.level });
      }
    }
  }
  return out;
}
