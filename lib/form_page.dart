import 'package:flutter/material.dart';

import 'format.dart';
import 'main.dart' show db;
import 'receipt.dart' show findTotal;
import 'theme.dart';
import 'utang.dart' show arahKu, namaLawan, rencanaBayar;

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
  const FormPage({
    this.ai,
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
  // Dari AI: 'biasa' | 'utang_baru' | 'pelunasan'; arah 'utang' (aku berutang) | 'piutang'.
  String jenis = 'biasa';
  String? nama, arah;
  bool kurangiUtang = true;

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
        if (ai['jenis'] == 'utang_baru' || ai['jenis'] == 'pelunasan') {
          if (ai['arah'] == 'utang' || ai['arah'] == 'piutang') {
            jenis = ai['jenis'];
            arah = ai['arah'];
            final nm = ai['nama'];
            nama = nm is String && nm.trim().isNotEmpty ? nm.trim() : null;
          }
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
    };
    setState(() => busy = true);
    String? info;
    try {
      final r = widget.row;
      if (r == null && jenis == 'utang_baru') {
        await db.from('utang').insert({
          'nama': nama ?? data['toko'],
          'arah': arah,
          'jumlah': n,
          'catatan': widget.sourceText,
        });
        info = 'Tersimpan di Pinjaman';
      } else {
        r == null
            ? await db.from('trx').insert(data)
            : await db.from('trx').update(data).eq('id', r['id']);
        if (r == null && jenis == 'pelunasan' && kurangiUtang) {
          info = await _kurangiUtang(n);
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
    if (info != null) _toast(info);
    if (mounted) Navigator.pop(context, true);
  }

  /// Pelunasan: potong utang/piutang yang belum lunas atas nama yang sama, terlama dulu.
  Future<String> _kurangiUtang(int bayar) async {
    // Termasuk pinjaman yang dibagikan orang lain (arahnya dibalik di arahKu).
    final semua = await db
        .from('utang_v')
        .select()
        .gt('sisa', 0)
        .order('created_at');
    final cari = nama?.toLowerCase();
    final open = semua
        .where((u) => arahKu(u) == arah)
        .where((u) => cari == null || namaLawan(u).toLowerCase().contains(cari))
        .toList();
    if (open.isEmpty) {
      return 'Transaksi tersimpan. Tidak ada pinjaman ${nama ?? ''} yang belum selesai.';
    }
    await db.from('utang_bayar').insert(rencanaBayar(open, bayar));
    return 'Transaksi tersimpan & pinjaman ${nama ?? ''} diperbarui';
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
          if (widget.row == null && jenis != 'biasa') ...[
            _UtangInfo(
              jenis: jenis,
              nama: nama,
              arah: arah!,
              kurangi: kurangiUtang,
              onKurangi: (v) => setState(() => kurangiUtang = v),
              onBukan: () => setState(() => jenis = 'biasa'),
            ),
            const SizedBox(height: 12),
          ],
          if (jenis != 'utang_baru')
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: C.dark,
                selectedForegroundColor: Colors.white,
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
          if (jenis != 'utang_baru')
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
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
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
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : _save,
            child: Text(
              jenis == 'utang_baru' ? 'Simpan ke Pinjaman' : 'Simpan',
            ),
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

class _UtangInfo extends StatelessWidget {
  final String jenis, arah;
  final String? nama;
  final bool kurangi;
  final ValueChanged<bool> onKurangi;
  final VoidCallback onBukan;
  const _UtangInfo({
    required this.jenis,
    required this.nama,
    required this.arah,
    required this.kurangi,
    required this.onKurangi,
    required this.onBukan,
  });

  @override
  Widget build(BuildContext context) {
    final siapa = nama ?? 'seseorang';
    final judul = jenis == 'utang_baru'
        ? (arah == 'piutang'
              ? '$siapa meminjam darimu'
              : 'Kamu meminjam dari $siapa')
        : (arah == 'piutang'
              ? '$siapa mengembalikan pinjaman'
              : 'Kamu mengembalikan pinjaman ke $siapa');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        gradient: limeCard,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI: catatan pinjaman terdeteksi',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            judul,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          if (jenis == 'pelunasan')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: kurangi,
              onChanged: onKurangi,
              title: Text(
                'Perbarui catatan pinjaman $siapa juga',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onBukan,
              child: const Text('Bukan, transaksi biasa'),
            ),
          ),
        ],
      ),
    );
  }
}
