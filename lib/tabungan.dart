import 'package:flutter/material.dart';

import 'anim.dart';
import 'form_page.dart' show ymd;
import 'format.dart';
import 'main.dart' show db;
import 'theme.dart';

/// Baris dari view `tabungan_v` (punya `saldo`).
typedef Tab = Map<String, dynamic>;

/// Progres 0..1 menuju target; null kalau tanpa target.
double? progres(Tab t) {
  final target = t['target'] as num?;
  if (target == null || target <= 0) return null;
  return ((t['saldo'] as num) / target).clamp(0, 1).toDouble();
}

class TabunganPage extends StatefulWidget {
  const TabunganPage({super.key});
  @override
  State<TabunganPage> createState() => _TabunganPageState();
}

class _TabunganPageState extends State<TabunganPage> {
  List<Tab> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> load() async {
    try {
      final r = await db.from('tabungan_v').select().order('created_at');
      if (mounted) setState(() => rows = r);
    } catch (e) {
      _toast('Gagal memuat: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _form([Tab? row]) async {
    final nama = TextEditingController(text: row?['nama'] ?? '');
    final target = TextEditingController(
      text: row?['target'] == null ? '' : '${row!['target']}',
    );
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(row == null ? 'Tabungan baru' : 'Ubah tabungan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nama,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nama',
                hintText: 'mis. Dana darurat, Liburan',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: target,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target (opsional)',
                hintText: 'mis. 5jt',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              if (nama.text.trim().isEmpty) return;
              Navigator.pop(c, {
                'nama': nama.text.trim(),
                'target': target.text.trim().isEmpty
                    ? null
                    : parseNominal(target.text),
              });
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (data == null) return;
    final t = data['target'] as int?;
    if (data['target'] == null && target.text.trim().isNotEmpty ||
        (t != null && t <= 0)) {
      return _toast('Target tidak valid');
    }
    try {
      row == null
          ? await db.from('tabungan').insert(data)
          : await db.from('tabungan').update(data).eq('id', row['id']);
      await load();
    } catch (e) {
      _toast('Gagal simpan: $e');
    }
  }

  Future<void> _detail(Tab t) async {
    final aksi = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _Detail(row: t),
    );
    if (aksi == 'ubah') await _form(t);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<num>(0, (s, r) => s + (r['saldo'] as num));
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        title: const Text(
          'Tabungan',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.dark,
        foregroundColor: Colors.white,
        onPressed: () => _form(),
        icon: const Icon(Icons.add),
        label: const Text('Tabungan baru'),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: limeCard,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total tabungan',
                    style: TextStyle(color: Color(0xFF24361F)),
                  ),
                  const SizedBox(height: 4),
                  AnimatedRp(
                    total,
                    style: const TextStyle(
                      color: C.dark,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: TypingDots(color: C.green)),
              )
            else if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Belum ada tabungan. Buat target pertamamu!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.muted),
                  ),
                ),
              )
            else
              for (final (i, t) in rows.indexed)
                FadeIn(
                  key: ValueKey(t['id']),
                  index: i,
                  child: _TabTile(row: t, onTap: () => _detail(t)),
                ),
          ],
        ),
      ),
    );
  }
}

class _TabTile extends StatelessWidget {
  final Tab row;
  final VoidCallback onTap;
  const _TabTile({required this.row, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = progres(row);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFDDF3D2),
                      child: Icon(Icons.savings_outlined, color: C.dark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${row['nama']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    AnimatedRp(
                      row['saldo'] as num,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                if (p != null) ...[
                  const SizedBox(height: 10),
                  AnimatedBar(value: p, color: p >= 1 ? C.green : C.lime),
                  const SizedBox(height: 6),
                  Text(
                    p >= 1
                        ? 'Target ${rp(row['target'] as num)} tercapai 🎉'
                        : '${(p * 100).floor()}% dari ${rp(row['target'] as num)}',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatefulWidget {
  final Tab row;
  const _Detail({required this.row});
  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  late Tab row = widget.row;
  List<Map<String, dynamic>> isi = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _load() async {
    try {
      final t = await db
          .from('tabungan_v')
          .select()
          .eq('id', row['id'])
          .single();
      final i = await db
          .from('tabungan_isi')
          .select()
          .eq('tabungan_id', row['id'])
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          row = t;
          isi = i;
        });
      }
    } catch (e) {
      _toast('Gagal memuat: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _ubahSaldo(bool setor) async {
    final saldo = (row['saldo'] as num).toInt();
    final ctrl = TextEditingController();
    var catat = true;
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(setor ? 'Setor' : 'Tarik'),
        content: StatefulBuilder(
          builder: (c, set) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nominal',
                  hintText: 'mis. 100rb',
                  helperText: setor ? null : 'Saldo ${rp(saldo)}',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: catat,
                onChanged: (v) => set(() => catat = v ?? true),
                title: Text(
                  setor
                      ? 'Catat juga sebagai pengeluaran'
                      : 'Catat juga sebagai pemasukan',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, parseNominal(ctrl.text) ?? -1),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (n == null) return;
    if (n <= 0) return _toast('Nominal tidak valid');
    if (!setor && n > saldo) return _toast('Melebihi saldo ${rp(saldo)}');
    try {
      await db.from('tabungan_isi').insert({
        'tabungan_id': row['id'],
        'jumlah': setor ? n : -n,
      });
      // Supaya saldo bulanan ikut berubah (uang pindah ke/dari tabungan).
      if (catat) {
        await db.from('trx').insert({
          'toko': '${setor ? 'Setor' : 'Tarik'} tabungan ${row['nama']}',
          'kategori': 'tabungan',
          'tipe': setor ? 'keluar' : 'masuk',
          'jumlah': n,
          'tanggal': ymd(DateTime.now()),
        });
      }
      await _load();
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  Future<void> _hapus() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus tabungan ini?'),
        content: const Text('Riwayat setor & tariknya ikut terhapus.'),
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
    try {
      await db.from('tabungan').delete().eq('id', row['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = progres(row);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Text(
              '${row['nama']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Saldo', style: TextStyle(color: C.muted)),
                  AnimatedRp(
                    row['saldo'] as num,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (p != null) ...[
                    const SizedBox(height: 10),
                    AnimatedBar(
                      value: p,
                      color: p >= 1 ? C.green : C.lime,
                      height: 10,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(p * 100).floor()}% dari target ${rp(row['target'] as num)}',
                      style: const TextStyle(color: C.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ubahSaldo(true),
                    icon: const Icon(Icons.add),
                    label: const Text('Setor'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (row['saldo'] as num) > 0
                        ? () => _ubahSaldo(false)
                        : null,
                    icon: const Icon(Icons.remove),
                    label: const Text('Tarik'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Riwayat',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: TypingDots(color: C.green)),
              )
            else if (isi.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada setoran.',
                  style: TextStyle(color: C.muted),
                ),
              )
            else
              for (final (i, e) in isi.indexed)
                FadeIn(
                  key: ValueKey(e['id']),
                  index: i,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      (e['jumlah'] as num) > 0
                          ? Icons.south_west
                          : Icons.north_east,
                      color: (e['jumlah'] as num) > 0 ? C.income : C.expense,
                    ),
                    title: Text(
                      (e['jumlah'] as num) > 0
                          ? 'Setor ${rp(e['jumlah'] as num)}'
                          : 'Tarik ${rp(-(e['jumlah'] as num))}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${e['tanggal']}'),
                  ),
                ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'ubah'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Ubah'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: C.expense),
                    onPressed: _hapus,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
