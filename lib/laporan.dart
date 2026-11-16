import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'anim.dart';
import 'form_page.dart' show kategoriList;
import 'format.dart';
import 'main.dart' show db;
import 'pages.dart' show ShellState, BulanSwitcher, Trx;
import 'theme.dart';

/// Total pengeluaran per kategori, terbesar dulu.
List<MapEntry<String, int>> keluarPerKategori(List<Trx> rows) {
  final m = <String, int>{};
  for (final r in rows.where(
    (r) => r['tipe'] == 'keluar' && r['transfer'] == null,
  )) {
    final k = '${r['kategori']}';
    m[k] = (m[k] ?? 0) + (r['jumlah'] as num).toInt();
  }
  return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Status anggaran: 'aman' (<80%), 'hampir' (80-99%), 'lewat' (>=100%).
String statusAnggaran(int terpakai, int batas) {
  final p = terpakai / batas;
  return p >= 1 ? 'lewat' : (p >= 0.8 ? 'hampir' : 'aman');
}

/// CSV transaksi (dipisah koma, angka tanpa titik) untuk Excel/Sheets.
String keCsv(List<Trx> rows) {
  String sel(Object? v) {
    final s = '${v ?? ''}';
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final b = StringBuffer('tanggal,tipe,kategori,keterangan,jumlah\n');
  for (final r in rows.reversed) {
    b.writeln(
      [
        r['tanggal'],
        r['tipe'],
        r['kategori'],
        r['toko'],
        r['jumlah'],
      ].map(sel).join(','),
    );
  }
  return b.toString();
}

/// CSV umum: kolom = gabungan semua key (urut kemunculan), nilai bersarang jadi JSON.
String tabelCsv(List<Map<String, dynamic>> rows) {
  String sel(Object? v) {
    final s = v is Map || v is List ? jsonEncode(v) : '${v ?? ''}';
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final kol = <String>{for (final r in rows) ...r.keys}.toList();
  final b = StringBuffer('${kol.join(',')}\n');
  for (final r in rows) {
    b.writeln(kol.map((k) => sel(r[k])).join(','));
  }
  return b.toString();
}

/// Pengeluaran per tanggal (index 0 = tanggal 1).
List<int> keluarPerHari(List<Trx> rows, DateTime bulan) {
  final hari = List.filled(DateTime(bulan.year, bulan.month + 1, 0).day, 0);
  for (final r in rows.where(
    (r) => r['tipe'] == 'keluar' && r['transfer'] == null,
  )) {
    final d = DateTime.parse('${r['tanggal']}').day;
    hari[d - 1] += (r['jumlah'] as num).toInt();
  }
  return hari;
}

const _katWarna = {
  'makan': Color(0xFFE08A4F),
  'transport': Color(0xFF5B8BD0),
  'belanja': Color(0xFFD2A93B),
  'gaji': Color(0xFF4CAF50),
  'tagihan': Color(0xFF8A6BC4),
  'hiburan': Color(0xFFD4688C),
  'kesehatan': Color(0xFF3FA79B),
};

class LaporanPage extends StatelessWidget {
  final ShellState shell;
  const LaporanPage({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    final s = shell;
    final masuk = s.sum('masuk'), keluar = s.sum('keluar');
    final kat = keluarPerKategori(s.rows);
    final hari = keluarPerHari(s.rows, s.bulan);
    final maxHari = hari.fold(0, (a, b) => b > a ? b : a);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: s.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Laporan',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Ekspor CSV',
                  onPressed: s.rows.isEmpty ? null : () => _ekspor(context),
                  icon: const Icon(Icons.ios_share),
                ),
                IconButton(
                  tooltip: 'Backup semua data',
                  onPressed: () => _backup(context),
                  icon: const Icon(Icons.backup_outlined),
                ),
                BulanSwitcher(shell: s),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: C.dark,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selisih bulan ini',
                    style: TextStyle(color: Color(0xFFB8C4B5), fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rp(masuk - keluar),
                    style: TextStyle(
                      color: masuk >= keluar ? C.lime : const Color(0xFFF2A07A),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _Stat('▲ Masuk', masuk),
                      _Stat('▼ Keluar', keluar),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Panel(
              judul: 'Pengeluaran harian',
              child: SizedBox(
                height: 120,
                child: maxHari == 0
                    ? Center(
                        child: Text(
                          'Belum ada pengeluaran',
                          style: TextStyle(color: C.muted),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < hari.length; i++)
                            Expanded(
                              child: Tooltip(
                                message: 'Tgl ${i + 1}: ${rp(hari[i])}',
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1.5,
                                  ),
                                  height: hari[i] == 0
                                      ? 3
                                      : 3 + 117 * hari[i] / maxHari,
                                  decoration: BoxDecoration(
                                    color: hari[i] == maxHari
                                        ? C.expense
                                        : hari[i] == 0
                                        ? const Color(0xFFE6E9E2)
                                        : C.green,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              footer: maxHari == 0
                  ? null
                  : 'Tertinggi ${rp(maxHari)} · rata-rata ${rp(keluar ~/ hari.length)}/hari',
            ),
            const SizedBox(height: 12),
            _Panel(
              judul: 'Pengeluaran per kategori',
              child: kat.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'Belum ada pengeluaran',
                          style: TextStyle(color: C.muted),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final e in kat)
                          _KatBar(
                            nama: e.key,
                            jumlah: e.value,
                            persen: e.value / keluar,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            _Panel(
              judul: 'Anggaran bulan ini',
              footer: 'Ketuk kategori untuk atur batas',
              child: Column(
                children: [
                  for (final k in kategoriList.where((k) => k != 'gaji'))
                    _AnggaranRow(
                      kategori: k,
                      terpakai: {for (final e in kat) e.key: e.value}[k] ?? 0,
                      batas: s.anggaran[k],
                      onTap: () => _aturAnggaran(context, k),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on LaporanPage {
  Future<void> _ekspor(BuildContext context) async {
    final b = shell.bulan;
    final nama = 'keuangan-${b.year}-${b.month.toString().padLeft(2, '0')}.csv';
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(keCsv(shell.rows))),
            mimeType: 'text/csv',
            name: nama,
          ),
        ],
        fileNameOverrides: [nama],
        // iPad butuh posisi asal popover.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// Semua data milik user (dan menu yang dibagikan) sebagai beberapa file CSV.
  Future<void> _backup(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final m = ScaffoldMessenger.of(context);
    m.showSnackBar(const SnackBar(content: Text('Menyiapkan backup…')));
    try {
      // PostgREST membatasi 1000 baris per request, jadi ambil per halaman.
      Future<List<Map<String, dynamic>>> semua(String t) async {
        final out = <Map<String, dynamic>>[];
        for (var i = 0; ; i += 1000) {
          final r = await db.from(t).select().order('id').range(i, i + 999);
          out.addAll(r);
          if (r.length < 1000) return out;
        }
      }

      final tgl = DateTime.now().toIso8601String().substring(0, 10);
      final files = <XFile>[];
      for (final t in [
        'trx',
        'akun',
        'menu',
        'menu_item',
        'rutin',
        'anggaran',
      ]) {
        final rows = await semua(t);
        if (rows.isEmpty) continue;
        files.add(
          XFile.fromData(
            Uint8List.fromList(utf8.encode(tabelCsv(rows))),
            mimeType: 'text/csv',
            name: 'rupi-$t-$tgl.csv',
          ),
        );
      }
      m.hideCurrentSnackBar();
      if (files.isEmpty) {
        m.showSnackBar(const SnackBar(content: Text('Belum ada data')));
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          fileNameOverrides: [for (final f in files) f.name],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Backup gagal: $e')));
    }
  }

  Future<void> _aturAnggaran(BuildContext context, String k) async {
    final lama = shell.anggaran[k];
    final ctrl = TextEditingController(text: lama == null ? '' : '$lama');
    final hasil = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Anggaran ${k[0].toUpperCase()}${k.substring(1)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Batas per bulan',
            hintText: 'mis. 1,5jt',
          ),
        ),
        actions: [
          if (lama != null)
            TextButton(
              onPressed: () => Navigator.pop(c, 'hapus'),
              child: const Text('Hapus batas'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (hasil == null) return;
    if (hasil == 'hapus') return shell.setAnggaran(k, null);
    final n = parseNominal(hasil);
    if (n == null || n <= 0) return;
    await shell.setAnggaran(k, n);
  }
}

class _AnggaranRow extends StatelessWidget {
  final String kategori;
  final int terpakai;
  final int? batas;
  final VoidCallback onTap;
  const _AnggaranRow({
    required this.kategori,
    required this.terpakai,
    required this.batas,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final b = batas;
    final st = b == null ? null : statusAnggaran(terpakai, b);
    final warna = switch (st) {
      'lewat' => C.expense,
      'hampir' => const Color(0xFFD2A93B),
      _ => C.green,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${kategori[0].toUpperCase()}${kategori.substring(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  b == null
                      ? (terpakai > 0
                            ? '${rp(terpakai)} · atur batas'
                            : 'atur batas')
                      : '${rp(terpakai)} / ${rp(b)}',
                  style: TextStyle(
                    color: b == null ? C.muted : warna,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (b != null) ...[
              const SizedBox(height: 6),
              AnimatedBar(value: terpakai / b, color: warna),
              if (st != 'aman')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    st == 'lewat'
                        ? 'Lewat ${rp(terpakai - b)} dari batas'
                        : 'Sisa ${rp(b - terpakai)}, hampir habis',
                    style: TextStyle(color: warna, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int v;
  const _Stat(this.label, this.v);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFFB8C4B5), fontSize: 12),
        ),
        Text(
          rp(v),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  final String judul;
  final Widget child;
  final String? footer;
  const _Panel({required this.judul, required this.child, this.footer});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: C.card,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          judul,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 14),
        child,
        if (footer != null) ...[
          const SizedBox(height: 10),
          Text(footer!, style: TextStyle(color: C.muted, fontSize: 12)),
        ],
      ],
    ),
  );
}

class _KatBar extends StatelessWidget {
  final String nama;
  final int jumlah;
  final double persen;
  const _KatBar({
    required this.nama,
    required this.jumlah,
    required this.persen,
  });
  @override
  Widget build(BuildContext context) {
    final warna = _katWarna[nama] ?? C.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(radius: 5, backgroundColor: warna),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${nama[0].toUpperCase()}${nama.substring(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${(persen * 100).round()}%  ',
                style: TextStyle(color: C.muted, fontSize: 12),
              ),
              Text(
                rp(jumlah),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: persen,
              minHeight: 8,
              color: warna,
              backgroundColor: C.track,
            ),
          ),
        ],
      ),
    );
  }
}
