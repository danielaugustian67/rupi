import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "50");
const PROMPT =
  'Kamu pencatat keuangan pribadi Indonesia. Input berupa teks OCR struk atau kalimat bebas. ' +
  'Balas HANYA satu objek JSON tanpa penjelasan: ' +
  '{"jenis": "biasa" | "menu", "menu_id": number | null, "akun_id": number | null, ' +
  '"toko": string (keterangan singkat, huruf kapital di awal), "total": number, ' +
  '"tipe": "masuk" | "keluar" (arah uang dari sudut pandang AKU), ' +
  '"kategori": "makan"|"belanja"|"transport"|"tagihan"|"hiburan"|"kesehatan"|"gaji"|"lainnya"}. ' +
  'Aturan: rb/ribu/k = x1.000, jt/juta = x1.000.000. Membeli/membayar sesuatu = keluar. ' +
  'Gaji, bonus, terima/nerima uang = masuk. Struk: total = angka TOTAL akhir. ' +
  'User punya MENU CUSTOM (daftar di bawah). Pakai jenis "menu" dan menu_id yang cocok HANYA kalau kalimat ' +
  'jelas menyebut nama menu itu atau maksudnya jelas sama (mis. menu "Tagihan Rumah" untuk "bayar listrik rumah"). ' +
  'Untuk jenis menu, toko = isi item tanpa nama menunya. Kalau ragu, jenis "biasa" dan menu_id null. ' +
  'User juga punya KARTU (e-wallet/rekening, daftar di bawah). akun_id = id kartu yang disebut ' +
  '(mis. "pakai X", "dari X", "ke X"); kalau tidak disebut, null. Nama kartu jangan masuk ke toko. ' +
  'Contoh: ' +
  '"makan siang 25rb" -> {"jenis":"biasa","menu_id":null,"akun_id":null,"toko":"Makan siang","total":25000,"tipe":"keluar","kategori":"makan"}. ' +
  '"gaji 7,5jt" -> {"jenis":"biasa","menu_id":null,"akun_id":null,"toko":"Gaji","total":7500000,"tipe":"masuk","kategori":"gaji"}. ' +
  'Dengan kartu [{"id":3,"nama":"Dompet A"}]: "bensin 50rb pakai dompet a" -> ' +
  '{"jenis":"biasa","menu_id":null,"akun_id":3,"toko":"Bensin","total":50000,"tipe":"keluar","kategori":"transport"}. ' +
  'Dengan menu [{"id":7,"nama":"Tagihan Rumah"}]: "tagihan rumah listrik 300rb" -> ' +
  '{"jenis":"menu","menu_id":7,"akun_id":null,"toko":"Listrik","total":300000,"tipe":"keluar","kategori":"tagihan"}.';

// Versi web memanggil dari browser; auth tetap lewat JWT di header, bukan cookie.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

/// Objek JSON pertama yang valid dan punya field `total`.
function extractJson(s: string): Record<string, unknown> | null {
  for (let a = s.indexOf("{"); a >= 0; a = s.indexOf("{", a + 1)) {
    for (let b = s.indexOf("}", a); b >= 0; b = s.indexOf("}", b + 1)) {
      try {
        const j = JSON.parse(s.slice(a, b + 1));
        if (j && typeof j === "object" && !Array.isArray(j) && "total" in j) return j;
      } catch { /* coba potongan berikutnya */ }
    }
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const key = Deno.env.get("OPENROUTER_KEY");
  const models = (Deno.env.get("OPENROUTER_MODELS") ?? "")
    .split(",").map((m) => m.trim()).filter(Boolean);
  if (!key || models.length === 0) {
    console.error("ai_not_configured", { hasKey: !!key, models });
    return json({ error: "ai_not_configured" }, 503);
  }

  let text = "";
  try {
    text = String((await req.json())?.text ?? "").slice(0, 4000);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!text.trim()) return json({ error: "empty" }, 400);

  // Identitas user dari JWT (sudah diverifikasi gateway karena verify_jwt=true).
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: u, error: ue } = await admin.auth.getUser(token);
  if (ue || !u?.user) return json({ error: "unauthorized" }, 401);

  const { data: used, error: be } = await admin.rpc("bump_ai_usage", { p_user: u.user.id });
  if (be) return json({ error: "usage" }, 500);
  if ((used as number) > DAILY_LIMIT) return json({ error: "limit", limit: DAILY_LIMIT }, 429);

  // Menu yang boleh diakses user (RLS: miliknya + yang dibagikan).
  const userDb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const [{ data: menus }, { data: akuns }] = await Promise.all([
    userDb.from("menu").select("id,nama").limit(50),
    userDb.from("akun").select("id,nama").limit(30),
  ]);
  const menuIds = new Set((menus ?? []).map((m) => m.id));
  const akunIds = new Set((akuns ?? []).map((a) => a.id));
  const daftarMenu = "MENU CUSTOM user: " + JSON.stringify(menus ?? []) +
    "\nKARTU user: " + JSON.stringify(akuns ?? []);

  // App menyerah di 12 dtk lalu pakai form biasa; server berhenti lebih dulu.
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 10000);
  const start = Date.now();
  const call = (noReasoning: boolean) =>
    fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      signal: ctrl.signal,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        ...(models.length === 1 ? { model: models[0] } : { models }),
        temperature: 0,
        max_tokens: noReasoning ? 300 : 2000,
        // Mode berpikir bikin lambat; matikan kalau model mengizinkan.
        ...(noReasoning ? { reasoning: { enabled: false } } : { reasoning: { effort: "low" } }),
        messages: [
          { role: "system", content: PROMPT + "\n" + daftarMenu },
          { role: "user", content: text },
        ],
      }),
    });
  try {
    let r = await call(true);
    if (r.status === 400) {
      const body = await r.text();
      if (!/reasoning/i.test(body)) {
        console.error("upstream", 400, body.slice(0, 500));
        return json({ error: "upstream", status: 400 }, 502);
      }
      // Model ini wajib reasoning: ulangi dengan reasoning minimal.
      r = await call(false);
    }
    if (!r.ok) {
      console.error("upstream", r.status, Date.now() - start, "ms", (await r.text()).slice(0, 500));
      return json({ error: "upstream", status: r.status }, 502);
    }
    const res = await r.json();
    const msg = res?.choices?.[0]?.message ?? {};
    const parsed = (typeof msg.content === "string" ? extractJson(msg.content) : null) ??
      (typeof msg.reasoning === "string" ? extractJson(msg.reasoning) : null);
    // Model gratis kadang meleset; nama yang disebut persis tetap menang (terpanjang dulu).
    const low = text.toLowerCase();
    const sebut = (rows: { id: number; nama: string }[] | null) =>
      (rows ?? []).filter((x) => low.includes(String(x.nama).toLowerCase()))
        .sort((a, b) => String(b.nama).length - String(a.nama).length)[0];
    // Jangan percaya id dari model kalau bukan milik/terbagi ke user.
    if (parsed && (parsed.jenis !== "menu" || !menuIds.has(parsed.menu_id as number))) {
      const cocok = sebut(menus);
      parsed.jenis = cocok ? "menu" : "biasa";
      parsed.menu_id = cocok?.id ?? null;
    }
    if (parsed && !akunIds.has(parsed.akun_id as number)) parsed.akun_id = sebut(akuns)?.id ?? null;
    console.log("model", res?.model, Date.now() - start, "ms", parsed ? JSON.stringify(parsed) : "unparseable");
    if (!parsed) console.error("unparseable", String(msg.content ?? "").slice(0, 300));
    return parsed ? json(parsed) : json({ error: "unparseable" }, 502);
  } catch (e) {
    console.error("fetch_failed", Date.now() - start, "ms", String(e));
    return json({ error: "timeout" }, 504);
  } finally {
    clearTimeout(t);
  }
});
