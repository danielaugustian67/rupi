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
