/**
 * 気象警報・注意報 — 気象庁の防災情報 XML フィード(公式・登録不要)。
 *
 * 以前は `jma.go.jp/bosai/warning/data/warning/*.json` を読んでいたが、
 * この非公式 JSON は 2026-05-28 を最後に更新が止まっており(全国どの府県でも
 * last-modified が同じ日付)、実際に大雨警報が出ていても空で返ってくる。
 * 地震(P2P)と予報 JSON は生きているので、警報だけがずっと発火しない状態だった。
 *
 * 公式フィードは「更新された文書へのリンク一覧」なので、**前回見た文書は
 * 引き直さない**。平常時に引く文書は毎回 0〜数件で済む。
 */
export type Warning = {
  areaCode: string; // class20 (7桁) 市町村コード
  code: string;
  name: string;
  status: string;
  kind: "flood" | "heavy_rain" | "landslide" | "tsunami" | "storm_surge" | "other";
  level: "special" | "warning" | "advisory";
};

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

const FEED = "https://www.data.jma.go.jp/developer/xml/feed/extra.xml";
/** フィード上の報種別。これ以外(土砂災害警戒情報・府県気象情報など)は別物。 */
const REPORT_TITLE = "気象特別警報・警報・注意報";

export type WarningDoc = { office: string; url: string; updated: string; warnings: Warning[] };

const tag = (xml: string, name: string): string | null => new RegExp(`<${name}[^>]*>([^<]*)</${name}>`).exec(xml)?.[1] ?? null;

/** フィードを読んで、府県予報区ごとの最新文書だけを返す(未取得。URL のみ)。 */
export async function fetchWarningFeed(): Promise<Array<{ office: string; url: string; updated: string }>> {
  const r = await fetch(FEED, { headers: { "User-Agent": "hinamichi/0.1" }, signal: AbortSignal.timeout(10000) });
  if (!r.ok) throw new Error(`jma feed ${r.status}`);
  const xml = await r.text();
  const latest = new Map<string, { office: string; url: string; updated: string }>();
  for (const m of xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)) {
    const e = m[1]!;
    if (tag(e, "title") !== REPORT_TITLE) continue;
    const url = tag(e, "id");
    const updated = tag(e, "updated");
    if (!url || !updated) continue;
    const office = /_VPWW\d+_(\d+)\.xml/.exec(url)?.[1];
    if (!office) continue;
    // 同じ府県予報区の古い版は捨てる。フィードには訂正報も並ぶ。
    const prev = latest.get(office);
    if (!prev || updated > prev.updated) latest.set(office, { office, url, updated });
  }
  return [...latest.values()];
}

/**
 * 1 文書から市町村ごとの警報を取り出す。
 *
 * 文書には府県予報区・一次細分区域・市町村をまとめた地域・市町村の 4 通りの
 * まとめ方が入っている。欲しいのは市町村なので、その `codeType` の塊だけ見る。
 */
export function parseWarningDoc(xml: string): Warning[] {
  const out: Warning[] = [];
  for (const item of xml.matchAll(/<Item>([\s\S]*?)<\/Item>/g)) {
    const body = item[1]!;
    // 市町村コードが並んでいる塊でなければ、同じ内容の粗いまとめなので飛ばす。
    if (!/<Areas codeType="気象・地震・火山情報／市町村等">/.test(body)) continue;
    const kinds: Array<{ code: string; status: string }> = [];
    for (const k of body.matchAll(/<Kind>([\s\S]*?)<\/Kind>/g)) {
      const kb = k[1]!;
      const name = tag(kb, "Name") ?? "";
      const code = tag(kb, "Code");
      // 解除は「出ていない」と同じ。
      if (!code || name.includes("解除")) continue;
      kinds.push({ code, status: tag(kb, "Status") ?? "発表" });
    }
    if (!kinds.length) continue;
    const areas = [...body.matchAll(/<Area>([\s\S]*?)<\/Area>/g)]
      .map((a) => tag(a[1]!, "Code"))
      .filter((c): c is string => !!c);
    for (const areaCode of areas) {
      for (const { code, status } of kinds) {
        const def = WARN_CODES[code];
        if (!def) continue;
        out.push({ areaCode, code, name: def.name, status, kind: def.kind, level: def.level });
      }
    }
  }
  return out;
}

/** 1 府県予報区の文書を引いて解析する。落ちたら null(他の府県は続ける)。 */
export async function fetchWarningDoc(e: { office: string; url: string; updated: string }): Promise<WarningDoc | null> {
  try {
    const r = await fetch(e.url, { headers: { "User-Agent": "hinamichi/0.1" }, signal: AbortSignal.timeout(10000) });
    if (!r.ok) return null;
    return { ...e, warnings: parseWarningDoc(await r.text()) };
  } catch {
    return null;
  }
}

/** 1 市区町村にいま出ている警報。アプリからの問い合わせ用(フィードは使わない)。 */
export async function fetchWarningsFor(office: string, class20: string): Promise<Warning[]> {
  const feed = await fetchWarningFeed().catch(() => []);
  const mine = feed.find((e) => e.office === office);
  if (!mine) return [];
  const doc = await fetchWarningDoc(mine);
  return doc?.warnings.filter((w) => w.areaCode === class20) ?? [];
}
