import 'package:flutter/material.dart';

import 'anim.dart';
import 'form_page.dart' show ymd;
import 'format.dart';
import 'main.dart' show db;
import 'theme.dart';

/// Baris dari view `utang_v` (punya `terbayar` & `sisa`).
typedef Utang = Map<String, dynamic>;

String get myId => db.auth.currentUser!.id;

bool milikku(Utang r, [String? me]) => r['user_id'] == (me ?? myId);

/// Arah dari sudut pandangku: 'piutang' = aku meminjamkan, 'utang' = aku meminjam.
/// Pinjaman yang dibagikan orang lain arahnya dibalik.
String arahKu(Utang r, [String? me]) =>
    milikku(r, me) ? r['arah'] : (r['arah'] == 'utang' ? 'piutang' : 'utang');

/// Nama lawan: untuk pinjaman milik orang lain, pakai bagian depan email pemiliknya.
String namaLawan(Utang r, [String? me]) {
  if (milikku(r, me)) return '${r['nama']}';
  return '${r['pemilik_email'] ?? 'teman'}'.split('@').first;
}

/// Total sisa yang belum kembali untuk satu arah (sudut pandangku).
int sisaTotal(List<Utang> rows, String arah, [String? me]) => rows
    .where((r) => arahKu(r, me) == arah)
    .fold(0, (s, r) => s + (r['sisa'] as num).toInt());

/// Bagi [bayar] ke pinjaman yang masih ada sisa, terlama dulu.
/// Hasil: [{'utang_id': .., 'jumlah': ..}] untuk di-insert ke `utang_bayar`.
List<Map<String, dynamic>> rencanaBayar(List<Utang> open, int bayar) {
  final out = <Map<String, dynamic>>[];
  for (final u in open) {
    final sisa = (u['sisa'] as num).toInt();
    if (bayar <= 0) break;
    if (sisa <= 0) continue;
    final j = bayar < sisa ? bayar : sisa;
    out.add({'utang_id': u['id'], 'jumlah': j});
    bayar -= j;
  }
  return out;
}

class UtangPage extends StatefulWidget {
  const UtangPage({super.key});
  @override
  State<UtangPage> createState() => _UtangPageState();
}

class _UtangPageState extends State<UtangPage> {
  List<Utang> rows = [];
  bool loading = true;
  String arah = 'piutang';

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
      final r = await db
          .from('utang_v')
          .select()
          .order('created_at', ascending: false);
      // Yang masih ada sisa di atas, yang sudah lunas di bawah (sort stabil).
      int lunas(Utang x) => (x['sisa'] as num) == 0 ? 1 : 0;
      r.sort((a, b) => lunas(a).compareTo(lunas(b)));
      if (mounted) setState(() => rows = r);
    } catch (e) {
      _toast('Gagal memuat: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _form([Utang? row]) async {
    final data = await showModalBottomSheet<Utang>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _UtangForm(row: row, arah: arah),
    );
    if (data == null) return;
    try {
      row == null
          ? await db.from('utang').insert(data)
          : await db.from('utang').update(data).eq('id', row['id']);
      await load();
    } catch (e) {
      _toast('Gagal simpan: $e');
    }
  }

  Future<void> _detail(Utang r) async {
    final aksi = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _Detail(row: r),
    );
    if (aksi == 'ubah') await _form(r);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final shown = rows.where((r) => arahKu(r) == arah).toList();
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        title: const Text(
          'Pinjaman',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.dark,
        foregroundColor: Colors.white,
        onPressed: () => _form(),
        icon: const Icon(Icons.add),
        label: Text(arah == 'piutang' ? 'Dipinjamkan' : 'Pinjamanku'),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Row(
              children: [
                _Ringkas(
                  'Dipinjamkan (sisa)',
                  sisaTotal(rows, 'piutang'),
                  C.income,
                ),
                const SizedBox(width: 10),
                _Ringkas(
                  'Pinjamanku (sisa)',
                  sisaTotal(rows, 'utang'),
                  C.expense,
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'piutang', label: Text('Dipinjamkan')),
                ButtonSegment(value: 'utang', label: Text('Pinjamanku')),
              ],
              selected: {arah},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: C.dark,
                selectedForegroundColor: Colors.white,
              ),
              onSelectionChanged: (v) => setState(() => arah = v.first),
            ),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: TypingDots(color: C.green)),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    arah == 'piutang'
                        ? 'Belum ada yang meminjam darimu.'
                        : 'Kamu belum punya pinjaman.',
                    style: const TextStyle(color: C.muted),
                  ),
                ),
              )
            else
              for (final (i, r) in shown.indexed)
                FadeIn(
                  key: ValueKey(r['id']),
                  index: i,
                  child: _UtangTile(row: r, onTap: () => _detail(r)),
                ),
          ],
        ),
      ),
    );
  }
}

class _Ringkas extends StatelessWidget {
  final String label;
  final int v;
  final Color warna;
  const _Ringkas(this.label, this.v, this.warna);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 4),
          AnimatedRp(
            v,
            style: TextStyle(
              color: warna,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    ),
  );
}

class _UtangTile extends StatelessWidget {
  final Utang row;
  final VoidCallback onTap;
  const _UtangTile({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final jumlah = (row['jumlah'] as num).toInt();
    final terbayar = (row['terbayar'] as num).toInt();
    final sisa = (row['sisa'] as num).toInt();
    final lunas = sisa == 0;
    final tempo = row['jatuh_tempo'] as String?;
    final telat =
        !lunas && tempo != null && tempo.compareTo(ymd(DateTime.now())) < 0;
    final bersama = !milikku(row) || row['pihak_email'] != null;
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
                    Expanded(
                      child: Text(
                        namaLawan(row),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (bersama)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.people_alt_outlined,
                          size: 16,
                          color: C.muted,
                          semanticLabel: 'Dibagikan',
                        ),
                      ),
                    if (lunas)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDF3D2),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Lunas',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: C.income,
                          ),
                        ),
                      )
                    else
                      Text(
                        'sisa ${rp(sisa)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedBar(
                  value: jumlah == 0 ? 0 : terbayar / jumlah,
                  color: lunas ? C.green : C.lime,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    'Kembali ${rp(terbayar)} dari ${rp(jumlah)}',
                    if (tempo != null) 'tempo $tempo',
                  ].join(' · '),
                  style: TextStyle(
                    color: telat ? C.expense : C.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rincian satu pinjaman: riwayat pengembalian + catat pengembalian.
class _Detail extends StatefulWidget {
  final Utang row;
  const _Detail({required this.row});
  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  late Utang row = widget.row;
  List<Map<String, dynamic>> bayar = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await db.from('utang_v').select().eq('id', row['id']).single();
      final b = await db
          .from('utang_bayar')
          .select()
          .eq('utang_id', row['id'])
          .order('tanggal', ascending: false);
      if (mounted) {
        setState(() {
          row = u;
          bayar = b;
        });
      }
    } catch (e) {
      _toast('Gagal memuat: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _catatBayar() async {
    final sisa = (row['sisa'] as num).toInt();
    final ctrl = TextEditingController(text: '$sisa');
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Catat pengembalian'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Nominal',
            helperText: 'Sisa ${rp(sisa)}. Boleh sebagian, mis. 50rb',
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
    if (n <= 0 || n > sisa) return _toast('Nominal harus 1 sampai ${rp(sisa)}');
    try {
      await db.from('utang_bayar').insert({'utang_id': row['id'], 'jumlah': n});
      await _load();
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  Future<void> _hapusBayar(Map<String, dynamic> b) async {
    try {
      await db.from('utang_bayar').delete().eq('id', b['id']);
      await _load();
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  Future<void> _hapus() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus pinjaman ini?'),
        content: const Text('Riwayat pengembaliannya ikut terhapus.'),
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
      await db.from('utang').delete().eq('id', row['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final jumlah = (row['jumlah'] as num).toInt();
    final terbayar = (row['terbayar'] as num).toInt();
    final sisa = (row['sisa'] as num).toInt();
    final punyaku = milikku(row);
    final ket = arahKu(row) == 'piutang'
        ? '${namaLawan(row)} meminjam darimu'
        : 'Kamu meminjam dari ${namaLawan(row)}';
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
              ket,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (!punyaku)
              Text(
                'Dibagikan oleh ${row['pemilik_email']}',
                style: const TextStyle(color: C.muted, fontSize: 12),
              )
            else if (row['pihak_email'] != null)
              Text(
                'Dibagikan ke ${row['pihak_email']}',
                style: const TextStyle(color: C.muted, fontSize: 12),
              ),
            if ((row['catatan'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${row['catatan']}',
                  style: const TextStyle(color: C.muted),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Angka('Total', jumlah, C.text),
                      _Angka('Sudah kembali', terbayar, C.income),
                      _Angka('Sisa', sisa, sisa == 0 ? C.muted : C.expense),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedBar(
                    value: jumlah == 0 ? 0 : terbayar / jumlah,
                    color: sisa == 0 ? C.green : C.lime,
                    height: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (sisa > 0)
              FilledButton.icon(
                onPressed: _catatBayar,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Catat pengembalian'),
              ),
            const SizedBox(height: 16),
            const Text(
              'Riwayat pengembalian',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: TypingDots(color: C.green)),
              )
            else if (bayar.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada pengembalian.',
                  style: TextStyle(color: C.muted),
                ),
              )
            else
              for (final (i, b) in bayar.indexed)
                FadeIn(
                  key: ValueKey(b['id']),
                  index: i,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFDDF3D2),
                      child: Icon(Icons.check, color: C.income),
                    ),
                    title: Text(
                      rp(b['jumlah'] as num),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${b['tanggal']} · '
                      '${b['created_by'] == myId ? 'dicatat olehmu' : 'dicatat teman'}',
                    ),
                    // Hanya pencatat yang bisa menghapus (juga dijaga RLS).
                    trailing: b['created_by'] == myId
                        ? IconButton(
                            tooltip: 'Hapus pengembalian',
                            onPressed: () => _hapusBayar(b),
                            icon: const Icon(Icons.close, size: 18),
                          )
                        : null,
                  ),
                ),
            if (punyaku) ...[
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
                      style: OutlinedButton.styleFrom(
                        foregroundColor: C.expense,
                      ),
                      onPressed: _hapus,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Hapus'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  final String label;
  final int v;
  final Color warna;
  const _Angka(this.label, this.v, this.warna);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedRp(
            v,
            style: TextStyle(
              color: warna,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ],
    ),
  );
}

class _UtangForm extends StatefulWidget {
  final Utang? row;
  final String arah;
  const _UtangForm({this.row, required this.arah});
  @override
  State<_UtangForm> createState() => _UtangFormState();
}

class _UtangFormState extends State<_UtangForm> {
  late final nama = TextEditingController(text: widget.row?['nama'] ?? '');
  late final jumlah = TextEditingController(
    text: widget.row == null ? '' : '${widget.row!['jumlah']}',
  );
  late final catatan = TextEditingController(
    text: widget.row?['catatan'] ?? '',
  );
  late final email = TextEditingController(
    text: widget.row?['pihak_email'] ?? '',
  );
  late String arah = widget.row?['arah'] ?? widget.arah;
  late DateTime? tempo = widget.row?['jatuh_tempo'] == null
      ? null
      : DateTime.parse(widget.row!['jatuh_tempo']);
  String? err;

  void _simpan() {
    final n = parseNominal(jumlah.text);
    final mail = email.text.trim().toLowerCase();
    if (nama.text.trim().isEmpty) return setState(() => err = 'Isi nama');
    if (n == null || n <= 0) return setState(() => err = 'Nominal tidak valid');
    if (mail.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(mail)) {
      return setState(() => err = 'Email teman tidak valid');
    }
    if (mail.isNotEmpty && mail == db.auth.currentUser?.email?.toLowerCase()) {
      return setState(() => err = 'Itu email kamu sendiri');
    }
    Navigator.pop(context, {
      'nama': nama.text.trim(),
      'jumlah': n,
      'arah': arah,
      'catatan': catatan.text.trim().isEmpty ? null : catatan.text.trim(),
      'jatuh_tempo': tempo == null ? null : ymd(tempo!),
      'pihak_email': mail.isEmpty ? null : mail,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.row == null ? 'Catat pinjaman' : 'Ubah pinjaman',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'piutang',
                    label: Text('Aku meminjamkan'),
                  ),
                  ButtonSegment(value: 'utang', label: Text('Aku meminjam')),
                ],
                selected: {arah},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: C.dark,
                  selectedForegroundColor: Colors.white,
                ),
                onSelectionChanged: (v) => setState(() => arah = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nama,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama orang'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: jumlah,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal',
                  hintText: 'contoh: 150rb',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email teman (opsional)',
                  helperText: 'Kalau diisi, temanmu bisa ikut melihat & mencatat pengembalian',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: catatan,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: tempo ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => tempo = d);
                      },
                      icon: const Icon(Icons.event),
                      label: Text(
                        tempo == null
                            ? 'Jatuh tempo (opsional)'
                            : 'Tempo ${ymd(tempo!)}',
                      ),
                    ),
                  ),
                  if (tempo != null)
                    IconButton(
                      tooltip: 'Hapus tempo',
                      onPressed: () => setState(() => tempo = null),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              if (err != null)
                Text(err!, style: const TextStyle(color: C.expense)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _simpan, child: const Text('Simpan')),
            ],
          ),
        ),
      ),
    );
  }
}
