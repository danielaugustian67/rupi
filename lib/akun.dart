import 'dart:math';

import 'package:flutter/material.dart';

import 'format.dart';
import 'main.dart' show db;

/// Tambah/ubah/hapus kartu saldo. True kalau ada perubahan.
Future<bool> formAkun(BuildContext context, [Map<String, dynamic>? row]) async {
  final nama = TextEditingController(text: row?['nama'] ?? '');
  final awal = TextEditingController(
    text: row == null ? '' : '${row['saldo_awal']}',
  );
  final aksi = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(row == null ? 'Kartu baru' : 'Ubah kartu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nama,
            autofocus: row == null,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama kartu',
              hintText: 'mis. E-wallet, rekening bank',
            ),
          ),
          TextField(
            controller: awal,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Saldo awal',
              helperText: 'Saldo sekarang sebelum dicatat di Rupi',
            ),
          ),
        ],
      ),
      actions: [
        if (row != null)
          TextButton(
            onPressed: () => Navigator.pop(c, 'hapus'),
            child: const Text('Hapus'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () {
            if (nama.text.trim().isNotEmpty) Navigator.pop(c, 'simpan');
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  if (aksi == null || !context.mounted) return false;
  void toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  try {
    if (aksi == 'hapus') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Hapus kartu ${row!['nama']}?'),
          content: const Text(
            'Transaksinya tetap ada, hanya tidak terhubung ke kartu mana pun.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );
      if (ok != true) return false;
      await db.from('akun').delete().eq('id', row!['id']);
      return true;
    }
    final a = awal.text.trim().isEmpty ? 0 : parseNominal(awal.text);
    if (a == null) {
      toast('Saldo awal tidak valid');
      return false;
    }
    final data = {'nama': nama.text.trim(), 'saldo_awal': a};
    row == null
        ? await db.from('akun').insert(data)
        : await db.from('akun').update(data).eq('id', row['id']);
    return true;
  } catch (e) {
    if (context.mounted) toast('Gagal: $e');
    return false;
  }
}

/// ID acak untuk memasangkan dua baris transfer (UUID v4).
String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Pindah saldo antar kartu: 2 baris trx (keluar & masuk) kategori 'transfer',
/// tidak dihitung sebagai pemasukan/pengeluaran.
Future<bool> formTransfer(
  BuildContext context,
  List<Map<String, dynamic>> akun,
) async {
  if (akun.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Buat minimal 2 kartu dulu di Beranda')),
    );
    return false;
  }
  Object? dari = akun[0]['id'], ke = akun[1]['id'];
  final jml = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Transfer antar kartu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, nilai, ganti) in [
              ('Dari', dari, (Object? v) => dari = v),
              ('Ke', ke, (Object? v) => ke = v),
            ])
              DropdownButtonFormField<Object?>(
                key: ValueKey('$label$nilai'),
                initialValue: nilai,
                decoration: InputDecoration(labelText: label),
                items: [
                  for (final a in akun)
                    DropdownMenuItem(
                      value: a['id'],
                      child: Text('${a['nama']}'),
                    ),
                ],
                onChanged: (v) => set(() => ganti(v)),
              ),
            TextField(
              controller: jml,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah (Rp)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  void toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  final n = parseNominal(jml.text);
  if (n == null || n <= 0) {
    toast('Jumlah tidak valid');
    return false;
  }
  if (dari == ke) {
    toast('Kartu asal dan tujuan harus beda');
    return false;
  }
  String nama(Object? id) => '${akun.firstWhere((a) => a['id'] == id)['nama']}';
  final u = _uuid();
  final tgl = DateTime.now().toIso8601String().substring(0, 10);
  final dasar = {
    'kategori': 'transfer',
    'jumlah': n,
    'tanggal': tgl,
    'transfer': u,
  };
  try {
    // Satu request = satu statement, jadi kedua baris masuk bersamaan.
    await db.from('trx').insert([
      {
        ...dasar,
        'toko': 'Transfer ke ${nama(ke)}',
        'tipe': 'keluar',
        'akun_id': dari,
      },
      {
        ...dasar,
        'toko': 'Transfer dari ${nama(dari)}',
        'tipe': 'masuk',
        'akun_id': ke,
      },
    ]);
    return true;
  } catch (e) {
    if (context.mounted) toast('Gagal: $e');
    return false;
  }
}

/// Hapus kedua sisi transfer.
Future<bool> hapusTransfer(
  BuildContext context,
  Map<String, dynamic> row,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('${row['toko']}'),
      content: Text(
        '${rp(row['jumlah'] as num)} · ${row['tanggal']}\n\n'
        'Transfer tidak bisa diubah. Hapus lalu buat ulang kalau salah.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Tutup'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Hapus transfer'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await db.from('trx').delete().eq('transfer', row['transfer']);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
    return false;
  }
}
