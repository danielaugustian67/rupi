import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "50");
const PROMPT =
  'Kamu pencatat keuangan pribadi Indonesia. Input berupa teks OCR struk atau kalimat bebas. ' +
  'Balas HANYA satu objek JSON tanpa penjelasan: ' +
  '{"jenis": "biasa" | "utang_baru" | "pelunasan", ' +
  '"toko": string (keterangan singkat, huruf kapital di awal; pakai kata "pinjaman", bukan "utang"), "total": number, ' +
  '"tipe": "masuk" | "keluar" (arah uang dari sudut pandang AKU), ' +
  '"kategori": "makan"|"belanja"|"transport"|"tagihan"|"hiburan"|"kesehatan"|"gaji"|"lainnya", ' +
  '"nama": nama orang lain atau null, ' +
  '"arah": "piutang" (orang lain meminjam dari AKU) | "utang" (AKU meminjam dari orang lain) | null}. ' +
  'Aturan: rb/ribu/k = x1.000, jt/juta = x1.000.000. Membeli/membayar sesuatu = keluar. ' +
  'Gaji, bonus, terima/nerima uang = masuk. Struk: total = angka TOTAL akhir. ' +
  'jenis utang_baru = ada pinjaman/utang baru (belum dikembalikan). ' +
  'jenis pelunasan = pinjaman/utang dibayar/dicicil/dikembalikan. Selain itu jenis biasa dengan nama & arah null. ' +
  'Contoh: ' +
  '"makan bakso 25rb" -> {"jenis":"biasa","toko":"Bakso","total":25000,"tipe":"keluar","kategori":"makan","nama":null,"arah":null}. ' +
  '"gaji 7,5jt" -> {"jenis":"biasa","toko":"Gaji","total":7500000,"tipe":"masuk","kategori":"gaji","nama":null,"arah":null}. ' +
  '"budi pinjam uang 100rb" -> {"jenis":"utang_baru","toko":"Pinjaman ke Budi","total":100000,"tipe":"keluar","kategori":"lainnya","nama":"Budi","arah":"piutang"}. ' +
  '"aku utang ke sari 50rb" -> {"jenis":"utang_baru","toko":"Pinjaman dari Sari","total":50000,"tipe":"masuk","kategori":"lainnya","nama":"Sari","arah":"utang"}. ' +
  '"nerima utang dari budi 300rb" -> {"jenis":"pelunasan","toko":"Pengembalian pinjaman Budi","total":300000,"tipe":"masuk","kategori":"lainnya","nama":"Budi","arah":"piutang"}. ' +
  '"bayar utang ke sari 50rb" -> {"jenis":"pelunasan","toko":"Kembalikan pinjaman Sari","total":50000,"tipe":"keluar","kategori":"lainnya","nama":"Sari","arah":"utang"}.';

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
          { role: "system", content: PROMPT },
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
