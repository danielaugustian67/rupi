import 'package:flutter/material.dart';

import 'format.dart';
import 'main.dart' show db;
import 'theme.dart';

/// Transaksi tiap bulan yang dicatat otomatis (rpc jalankan_rutin saat app dibuka).
class RutinPage extends StatefulWidget {
  const RutinPage({super.key});
  @override
  State<RutinPage> createState() => _RutinPageState();
}

class _RutinPageState extends State<RutinPage> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await db.from('rutin').select().order('hari', ascending: true);
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memuat: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _hapus(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Berhenti mencatat "${r['toko']}"?'),
        content: const Text('Transaksi yang sudah tercatat tetap ada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hentikan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('rutin').delete().eq('id', r['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: C.bg,
      title: const Text(
        'Transaksi rutin',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Belum ada. Saat menambah transaksi, aktifkan "Ulangi tiap bulan" '
              'untuk tagihan, langganan, atau gaji.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final r in rows)
                Card(
                  color: C.card,
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.repeat),
                    title: Text('${r['toko']}'),
                    subtitle: Text(
                      'Tiap tanggal ${r['hari']} · berikutnya ${r['berikut']}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${r['tipe'] == 'masuk' ? '▲' : '▼'} ${rp(r['jumlah'] as num)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: r['tipe'] == 'masuk' ? C.income : C.expense,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hentikan',
                          icon: const Icon(Icons.close),
                          onPressed: () => _hapus(r),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}

/// Tanggal jatuh tempo berikutnya untuk rutin yang dibuat dari transaksi [tgl].
({int hari, DateTime berikut}) jadwalRutin(DateTime tgl) {
  final hari = tgl.day > 28 ? 28 : tgl.day;
  return (hari: hari, berikut: DateTime(tgl.year, tgl.month + 1, hari));
}
