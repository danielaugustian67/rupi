import 'package:flutter/material.dart';

import 'format.dart';
import 'main.dart' show db;
import 'receipt.dart' show findTotal;
import 'rutin.dart' show jadwalRutin;
import 'theme.dart';

const kategoriList = [
  'makan',
  'belanja',
  'transport',
  'tagihan',
  'hiburan',
  'kesehatan',
  'gaji',
  'tabungan',
  'lainnya',
];

String ymd(DateTime d) => d.toIso8601String().substring(0, 10);

/// Form tambah/edit transaksi.
/// [sourceText]: teks OCR struk ([isReceipt]) atau kalimat bebas, diisi otomatis + AI.
class FormPage extends StatefulWidget {
  final String sourceText;
  final bool isReceipt;
  final Map<String, dynamic>? row; // null = transaksi baru
  final String tipe;
  final Map<String, dynamic>?
  ai; // hasil AI; null = AI mati/gagal, pakai tebakan biasa
  final List<Map<String, dynamic>> akun; // kartu saldo yang bisa dipilih
  const FormPage({
    this.ai,
    this.akun = const [],
    super.key,
    this.sourceText = '',
    this.isReceipt = false,
    this.row,
    this.tipe = 'keluar',
  });
  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final toko = TextEditingController();
  final jumlah = TextEditingController();
  String kategori = 'lainnya';
  late String tipe = widget.tipe;
  DateTime tanggal = DateTime.now();
  bool busy = false;
  Object? akunId; // null = tanpa kartu
  bool ulang = false; // juga buat transaksi rutin bulanan

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    if (r != null) {
      toko.text = '${r['toko']}';
      jumlah.text = '${r['jumlah']}';
      if (kategoriList.contains(r['kategori'])) kategori = r['kategori'];
      tipe = r['tipe'] == 'masuk' ? 'masuk' : 'keluar';
      tanggal = DateTime.tryParse('${r['tanggal']}') ?? tanggal;
      akunId = r['akun_id'];
      return;
    }
    final src = widget.sourceText;
    if (src.isEmpty) return;
    // Nominal dari regex langsung tampil; AI menyusul melengkapi.
    final n = widget.isReceipt ? findTotal(src) : parseNominal(src);
    jumlah.text = n?.toString() ?? '';
    if (!widget.isReceipt) {
      toko.text = src;
      // Tebakan cepat tanpa AI, supaya tetap benar kalau AI gagal.
      if (RegExp(
        r'\b(gaji|bonus|thr|lembur\w*|terima|nerima|menerima|diterima|dapat|dapet|transferan|dibayar|dikembalikan)\b',
        caseSensitive: false,
      ).hasMatch(src)) {
        tipe = 'masuk';
        if (src.toLowerCase().contains('gaji')) kategori = 'gaji';
      }
    }
    final ai = widget.ai;
    if (ai != null) {
      {
        if (ai['toko'] is String) toko.text = ai['toko'];
        if (kategoriList.contains(ai['kategori'])) kategori = ai['kategori'];
        if (ai['tipe'] == 'masuk' || ai['tipe'] == 'keluar') tipe = ai['tipe'];
        if (widget.akun.any((a) => a['id'] == ai['akun_id'])) {
          akunId = ai['akun_id'];
        }
        if (jumlah.text.isEmpty && ai['total'] is num) {
          jumlah.text = '${(ai['total'] as num).round()}';
        }
      }
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pilihTanggal() async {
    final d = await showDatePicker(
      context: context,
      initialDate: tanggal,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => tanggal = d);
  }

  Future<void> _save() async {
    final n = int.tryParse(jumlah.text.replaceAll(RegExp(r'[.,\s]'), ''));
    if (n == null || n <= 0) return _toast('Jumlah harus angka > 0');
    final data = {
      'toko': toko.text.trim().isEmpty ? '-' : toko.text.trim(),
      'kategori': kategori,
      'tipe': tipe,
      'jumlah': n,
      'tanggal': ymd(tanggal),
      'akun_id': akunId,
    };
    setState(() => busy = true);
    try {
      final r = widget.row;
      r == null
          ? await db.from('trx').insert(data)
          : await db.from('trx').update(data).eq('id', r['id']);
      if (r == null && ulang) {
        final j = jadwalRutin(tanggal);
        final rutin = Map.of(data)..remove('tanggal');
        try {
          await db.from('rutin').insert({
            ...rutin,
            'hari': j.hari,
            'berikut': ymd(j.berikut),
          });
        } catch (e) {
          // Transaksinya sudah tersimpan; jangan biarkan user menyimpan dobel.
          if (mounted) _toast('Tersimpan, tapi gagal membuat rutin: $e');
        }
      }
    } catch (e) {
      // Jangan tutup form kalau gagal simpan, supaya isian tidak hilang.
      if (mounted) {
        setState(() => busy = false);
        _toast('Gagal simpan: $e');
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus transaksi ini?'),
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
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await db.from('trx').delete().eq('id', widget.row!['id']);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        _toast('Gagal hapus: $e');
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        title: Text(
          widget.row == null ? 'Transaksi baru' : 'Edit transaksi',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (widget.row != null)
            IconButton(
              tooltip: 'Hapus',
              onPressed: busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: C.btn,
              selectedForegroundColor: C.onBtn,
            ),
            segments: const [
              ButtonSegment(value: 'keluar', label: Text('▼ Pengeluaran')),
              ButtonSegment(value: 'masuk', label: Text('▲ Pemasukan')),
            ],
            selected: {tipe},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => tipe = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: jumlah,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Jumlah (Rp)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: toko,
            decoration: const InputDecoration(labelText: 'Toko / keterangan'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // key: dropdown ikut berubah saat AI mengganti kategori.
            key: ValueKey(kategori),
            initialValue: kategori,
            decoration: const InputDecoration(labelText: 'Kategori'),
            items: [
              for (final k in kategoriList)
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: (v) => setState(() => kategori = v ?? kategori),
          ),
          if (widget.akun.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<Object?>(
              key: ValueKey('akun$akunId'),
              initialValue: akunId,
              decoration: const InputDecoration(labelText: 'Kartu'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tanpa kartu')),
                for (final a in widget.akun)
                  DropdownMenuItem(value: a['id'], child: Text('${a['nama']}')),
              ],
              onChanged: (v) => setState(() => akunId = v),
            ),
          ],
          const SizedBox(height: 12),
          Material(
            color: C.card,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Tanggal'),
              subtitle: Text(ymd(tanggal)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pilihTanggal,
            ),
          ),
          if (widget.row == null) ...[
            const SizedBox(height: 12),
            Material(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
              child: SwitchListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                secondary: const Icon(Icons.repeat),
                title: const Text('Ulangi tiap bulan'),
                subtitle: Text(
                  'Dicatat otomatis tiap tanggal ${jadwalRutin(tanggal).hari}',
                ),
                value: ulang,
                onChanged: (v) => setState(() => ulang = v),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : _save,
            child: const Text('Simpan'),
          ),
          if (widget.sourceText.isNotEmpty)
            ExpansionTile(
              title: Text(widget.isReceipt ? 'Teks hasil scan' : 'Teks asli'),
              children: [Text(widget.sourceText)],
            ),
        ],
      ),
    );
  }
}
