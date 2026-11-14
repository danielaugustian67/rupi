-- Jalankan sekali di Supabase Dashboard > SQL Editor.
create table trx (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  toko text not null,
  kategori text not null,
  tipe text not null default 'keluar' check (tipe in ('masuk', 'keluar')),
  jumlah bigint not null check (jumlah > 0),
  tanggal date not null default current_date,
  created_at timestamptz not null default now()
);

alter table trx enable row level security;

-- Tiap user hanya bisa lihat/ubah transaksinya sendiri.
create policy "own rows" on trx for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Kalau tabel trx sudah terlanjur dibuat dari versi lama, jalankan ini saja:
-- alter table trx add column tipe text not null default 'keluar' check (tipe in ('masuk', 'keluar'));

-- Utang & piutang (arah: 'utang' = aku berutang, 'piutang' = orang berutang ke aku)
create table public.utang (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nama text not null,
  arah text not null check (arah in ('utang','piutang')),
  jumlah bigint not null check (jumlah > 0),
  catatan text,
  jatuh_tempo date,
  lunas boolean not null default false,
  created_at timestamptz not null default now()
);
create index utang_user_idx on public.utang (user_id, lunas, created_at desc);
alter table public.utang enable row level security;
create policy "own rows" on public.utang for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- === Migrasi: pinjaman bersama + tabungan (diterapkan via MCP: pinjaman_bersama_dan_tabungan, tabungan_isi_cek_pemilik) ===
-- utang: kolom lunas dihapus; tambah pemilik_email (default email JWT) & pihak_email (teman yang ikut melihat).
-- RLS utang: select = pemilik atau email cocok pihak_email; insert/update/delete = pemilik.
-- utang_bayar: riwayat pengembalian; boleh dicatat pemilik atau pihak; hapus hanya pencatat.
-- View utang_v (security_invoker): + terbayar, sisa.
-- tabungan + tabungan_isi (setor positif / tarik negatif), view tabungan_v: + saldo.
-- Lihat migrasi di Supabase dashboard > Database > Migrations untuk SQL lengkap.
