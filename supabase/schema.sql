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

-- === Menu custom (migrasi via MCP: menu_custom, menu_select_pemilik) ===
-- Tabel lama utang, utang_bayar, tabungan, tabungan_isi (+ view) sudah dihapus.
-- profil(user_id, kode, email): kode teman 8 karakter, dibuat oleh rpc kode_saya().
-- menu(nama, ikon, pakai_tenggat, pakai_lunas, pakai_foto, target) milik user_id.
-- menu_anggota(menu_id, user_id, email): teman yang diundang lewat rpc tambah_anggota(menu, kode);
--   hanya pemilik menu yang bisa mengundang/mengeluarkan, anggota bisa keluar sendiri.
-- menu_item(judul, nominal, deskripsi, tanggal, tenggat, lunas, foto): pemilik & anggota boleh CRUD.
-- Akses dicek oleh boleh_akses_menu(menu_id) (security definer, tanpa rekursi RLS).
-- Storage bucket privat 'lampiran': path "<menu_id>/<file>", akses mengikuti menunya.
-- Lihat Supabase dashboard > Database > Migrations untuk SQL lengkap.
