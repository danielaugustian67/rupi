import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "50");

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

const rp = (n: number) => "Rp" + Math.round(n).toLocaleString("id-ID");

type Trx = { toko: string; kategori: string; tipe: string; jumlah: number; tanggal: string; transfer: string | null };
type Item = { judul: string; nominal: number; deskripsi: string | null; tanggal: string; tenggat: string | null; lunas: boolean; dibayar: number };
// Sudah dibayar: penuh kalau lunas, selain itu cicilan yang tercatat.
const bayar = (i: Item) => (i.lunas ? i.nominal : Math.min(i.dibayar ?? 0, i.nominal));
type Menu = {
  nama: string; pakai_lunas: boolean; pakai_tenggat: boolean; target: number | null; menu_item: Item[];
};

type Akun = { nama: string; saldo: number };
type Anggaran = { kategori: string; batas: number };

/// Ringkasan data user (3 bulan terakhir) sebagai konteks untuk AI.
function ringkas(trx: Trx[], menus: Menu[], akun: Akun[], anggaran: Anggaran[], today: string): string {
  const perBulan: Record<string, { masuk: number; keluar: number; kat: Record<string, number> }> = {};
  for (const t of trx) {
    if (t.transfer) continue; // pindah antar kartu, bukan pemasukan/pengeluaran
    const b = t.tanggal.slice(0, 7);
    const m = (perBulan[b] ??= { masuk: 0, keluar: 0, kat: {} });
    if (t.tipe === "masuk") m.masuk += t.jumlah;
    else {
      m.keluar += t.jumlah;
      m.kat[t.kategori] = (m.kat[t.kategori] ?? 0) + t.jumlah;
    }
  }
  const lines = [`Hari ini: ${today}.`, "Ringkasan per bulan:"];
  for (const [b, m] of Object.entries(perBulan).sort()) {
    const kat = Object.entries(m.kat).sort((a, c) => c[1] - a[1])
      .map(([k, v]) => `${k} ${rp(v)}`).join(", ");
    lines.push(`- ${b}: masuk ${rp(m.masuk)}, keluar ${rp(m.keluar)}, selisih ${rp(m.masuk - m.keluar)}. Keluar per kategori: ${kat || "-"}`);
  }
  if (trx.length === 0) lines.push("- belum ada transaksi");
  lines.push("Transaksi terbaru (maks 40):");
  for (const t of trx.slice(0, 40)) {
    lines.push(`- ${t.tanggal} ${t.tipe === "masuk" ? "+" : "-"}${rp(t.jumlah)} ${t.toko} (${t.kategori})`);
  }
  lines.push("Menu custom user (dibuat sendiri, mis. bill, tabungan, pinjaman):");
  for (const m of menus) {
    const items = m.menu_item ?? [];
    const total = items.reduce((a, i) => a + i.nominal, 0);
    const lunas = items.reduce((a, i) => a + bayar(i), 0);
    lines.push(`- Menu "${m.nama}": ${items.length} item, total ${rp(total)}` +
      (m.pakai_lunas ? `, lunas ${rp(lunas)}, belum lunas ${rp(total - lunas)}` : "") +
      (m.target ? `, target ${rp(m.target)}` : ""));
    for (const i of items.slice(0, 15)) {
      lines.push(`  · ${i.tanggal} ${i.judul} ${rp(i.nominal)}` +
        (m.pakai_lunas ? (i.lunas ? " [lunas]" : bayar(i) > 0 ? ` [dicicil ${rp(bayar(i))}, sisa ${rp(i.nominal - bayar(i))}]` : " [belum]") : "") +
        (m.pakai_tenggat && i.tenggat ? ` tempo ${i.tenggat}` : "") +
        (i.deskripsi ? ` (${i.deskripsi.slice(0, 80)})` : ""));
    }
  }
  if (menus.length === 0) lines.push("- belum ada");
  lines.push("Kartu (e-wallet/rekening) dan saldonya sekarang:");
  for (const a of akun) lines.push(`- ${a.nama}: ${rp(a.saldo)}`);
  if (akun.length === 0) lines.push("- belum ada");
  lines.push("Anggaran (batas pengeluaran per bulan per kategori; bandingkan dengan keluar per kategori bulan ini):");
  for (const a of anggaran) lines.push(`- ${a.kategori}: ${rp(a.batas)}`);
  if (anggaran.length === 0) lines.push("- belum diatur");
  return lines.join("\n");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const key = Deno.env.get("OPENROUTER_KEY");
  const models = (Deno.env.get("OPENROUTER_MODELS") ?? "")
    .split(",").map((m) => m.trim()).filter(Boolean);
  if (!key || models.length === 0) return json({ error: "ai_not_configured" }, 503);

  let messages: { role: string; content: string }[] = [];
  try {
    const raw = (await req.json())?.messages;
    if (!Array.isArray(raw)) throw 0;
    messages = raw
      .filter((m) => (m?.role === "user" || m?.role === "assistant") && typeof m?.content === "string")
      .slice(-10)
      .map((m) => ({ role: m.role, content: m.content.slice(0, 1500) }));
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (messages.at(-1)?.role !== "user") return json({ error: "empty" }, 400);

  const authHeader = req.headers.get("Authorization") ?? "";
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: u, error: ue } = await admin.auth.getUser(authHeader.replace(/^Bearer\s+/i, ""));
  if (ue || !u?.user) return json({ error: "unauthorized" }, 401);

  const { data: used, error: be } = await admin.rpc("bump_ai_usage", { p_user: u.user.id });
  if (be) return json({ error: "usage" }, 500);
  if ((used as number) > DAILY_LIMIT) return json({ error: "limit", limit: DAILY_LIMIT }, 429);

  // Baca data sebagai user itu sendiri (RLS tetap berlaku).
  const userDb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const now = new Date(Date.now() + 7 * 3600_000); // WIB
  const today = now.toISOString().slice(0, 10);
  const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 2, 1)).toISOString().slice(0, 10);
  const [r1, r2, r3, r4] = await Promise.all([
    userDb.from("trx").select("toko,kategori,tipe,jumlah,tanggal,transfer").gte("tanggal", from)
      .order("tanggal", { ascending: false }).limit(500),
    userDb.from("menu").select("nama,pakai_lunas,pakai_tenggat,target,menu_item(judul,nominal,deskripsi,tanggal,tenggat,lunas,dibayar)")
      .limit(30),
    userDb.from("akun_v").select("nama,saldo").limit(30),
    userDb.from("anggaran").select("kategori,batas").limit(30),
  ]);
  if (r1.error || r2.error || r3.error || r4.error) {
    console.error("db", r1.error?.message, r2.error?.message, r3.error?.message, r4.error?.message);
    return json({ error: "db" }, 500);
  }

  const system =
    "Kamu asisten keuangan pribadi di aplikasi Rupi. Jawab dalam Bahasa Indonesia yang ramah dan sopan, singkat " +
    "(maks ~6 kalimat atau poin pendek), tanpa markdown tabel. " +
    "Gunakan HANYA data di bawah untuk angka; jangan mengarang transaksi. Kalau data tidak cukup, bilang terus terang. " +
    "Format uang: Rp25.000.\n\n" +
    ringkas((r1.data ?? []) as Trx[], (r2.data ?? []) as Menu[], (r3.data ?? []) as Akun[], (r4.data ?? []) as Anggaran[], today);

  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 20000);
  const start = Date.now();
  const call = (noReasoning: boolean) =>
    fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      signal: ctrl.signal,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        ...(models.length === 1 ? { model: models[0] } : { models }),
        temperature: 0.3,
        max_tokens: noReasoning ? 600 : 2500,
        ...(noReasoning ? { reasoning: { enabled: false } } : { reasoning: { effort: "low" } }),
        messages: [{ role: "system", content: system }, ...messages],
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
      r = await call(false);
    }
    if (!r.ok) {
      console.error("upstream", r.status, (await r.text()).slice(0, 500));
      return json({ error: "upstream", status: r.status }, 502);
    }
    const res = await r.json();
    const reply = String(res?.choices?.[0]?.message?.content ?? "").trim();
    console.log("chat", res?.model, Date.now() - start, "ms", reply ? "ok" : "empty");
    return reply ? json({ reply }) : json({ error: "empty_reply" }, 502);
  } catch (e) {
    console.error("fetch_failed", Date.now() - start, "ms", String(e));
    return json({ error: "timeout" }, 504);
  } finally {
    clearTimeout(t);
  }
});
