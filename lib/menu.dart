import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException;

import 'anim.dart';
import 'form_page.dart' show ymd;
import 'format.dart';
import 'main.dart' show db;
import 'theme.dart';

typedef Row_ = Map<String, dynamic>;

/// Ikon yang bisa dipilih untuk menu (disimpan sebagai nama).
const ikonMenu = <String, IconData>{
  'folder': Icons.folder_outlined,
  'tagihan': Icons.receipt_long_outlined,
  'tabungan': Icons.savings_outlined,
  'pinjaman': Icons.swap_horiz,
  'belanja': Icons.shopping_bag_outlined,
  'rumah': Icons.home_outlined,
  'keluarga': Icons.people_outline,
  'kerja': Icons.work_outline,
};

IconData ikonDari(Row_ m) => ikonMenu[m['ikon']] ?? Icons.folder_outlined;

/// Total, lunas, sisa dari daftar item.
({int total, int lunas, int sisa}) ringkasItem(List<Row_> items) {
  var total = 0, lunas = 0;
  for (final i in items) {
    final n = (i['nominal'] as num).toInt();
    total += n;
    if (i['lunas'] == true) lunas += n;
  }
  return (total: total, lunas: lunas, sisa: total - lunas);
}

/// Kecilkan foto ke WebP (sisi terpanjang ±1280px) agar hemat storage.
Future<Uint8List> keWebp(Uint8List b) => FlutterImageCompress.compressWithList(
  b,
  minWidth: 1280,
  minHeight: 1280,
  quality: 70,
  format: CompressFormat.webp,
);

String? get _uid => db.auth.currentUser?.id;

void _toast(BuildContext c, String m) {
  if (c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
  }
}

/// Pesan error Postgres (mis. dari tambah_anggota) tanpa awalan teknis.
String _pesan(Object e) => e is PostgrestException ? e.message : '$e';

// ───────────────────────── Daftar menu ─────────────────────────

class MenuListPage extends StatefulWidget {
  const MenuListPage({super.key});
  @override
  State<MenuListPage> createState() => _MenuListPageState();
}

class _MenuListPageState extends State<MenuListPage> {
  List<Row_> menus = [];
  Map<int, List<Row_>> items = {};
  String? kode;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait<dynamic>([
        db.from('menu').select().order('created_at'),
        db.from('menu_item').select('menu_id,nominal,lunas'),
        db.rpc('kode_saya'),
      ]);
      final g = <int, List<Row_>>{};
      for (final i in r[1] as List) {
        (g[(i['menu_id'] as num).toInt()] ??= []).add(i);
      }
      if (mounted) {
        setState(() {
          menus = List<Row_>.from(r[0] as List);
          items = g;
          kode = r[2] as String?;
        });
      }
    } catch (e) {
      if (mounted) _toast(context, 'Gagal memuat: ${_pesan(e)}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _buka(Row_ m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MenuPage(menu: m)),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        title: const Text(
          'Menu',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.btn,
        foregroundColor: C.onBtn,
        onPressed: () async {
          final m = await formMenu(context);
          if (m != null) {
            await load();
            if (mounted) await _buka(m);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Menu baru'),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (kode != null) _KodeCard(kode: kode!),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: TypingDots(color: C.green)),
              )
            else if (menus.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Belum ada menu. Buat sendiri untuk tagihan, tabungan, '
                  'pinjaman, atau apa saja.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted),
                ),
              )
            else
              for (final (i, m) in menus.indexed)
                FadeIn(
                  key: ValueKey(m['id']),
                  index: i,
                  child: _MenuTile(
                    menu: m,
                    items: items[(m['id'] as num).toInt()] ?? const [],
                    onTap: () => _buka(m),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _KodeCard extends StatelessWidget {
  final String kode;
  const _KodeCard({required this.kode});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: limeCard,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kode temanmu',
                  style: TextStyle(color: Color(0xFF24361F), fontSize: 12),
                ),
                SelectableText(
                  kode,
                  style: const TextStyle(
                    color: C.dark,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const Text(
                  'Bagikan supaya teman bisa mengundangmu ke menunya.',
                  style: TextStyle(color: Color(0xFF24361F), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Salin kode',
            color: C.dark,
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: kode));
              if (context.mounted) _toast(context, 'Kode disalin');
            },
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final Row_ menu;
  final List<Row_> items;
  final VoidCallback onTap;
  const _MenuTile({
    required this.menu,
    required this.items,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final s = ringkasItem(items);
    final bersama = menu['user_id'] != _uid;
    final lunasOn = menu['pakai_lunas'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: C.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFDDF3D2),
                  child: Icon(ikonDari(menu), color: C.dark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${menu['nama']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        [
                          '${items.length} item',
                          if (bersama) 'dibagikan ke kamu',
                        ].join(' · '),
                        style: TextStyle(color: C.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedRp(
                      lunasOn ? s.sisa : s.total,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      lunasOn ? 'belum lunas' : 'total',
                      style: TextStyle(color: C.muted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Buat/ubah menu. Mengembalikan baris menu yang tersimpan, atau null kalau batal.
Future<Row_?> formMenu(BuildContext context, [Row_? m]) async {
  final nama = TextEditingController(text: m?['nama'] ?? '');
  final target = TextEditingController(
    text: m?['target'] == null ? '' : '${m!['target']}',
  );
  var ikon = (m?['ikon'] as String?) ?? 'folder';
  var tenggat = m?['pakai_tenggat'] == true;
  var lunas = m?['pakai_lunas'] ?? true;
  var foto = m?['pakai_foto'] == true;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(c).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: C.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Pratinjau langsung: ikon + nama seperti di daftar menu.
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: limeCard,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(ikonMenu[ikon], color: C.dark, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      m == null ? 'Menu baru' : 'Ubah menu',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: C.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nama,
                autofocus: m == null,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Nama menu',
                  hintText: 'mis. Tagihan, Tabungan',
                ),
              ),
              const SizedBox(height: 6),
              _Judul('Ikon'),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  for (final e in ikonMenu.entries)
                    _IkonTile(
                      ikon: e.value,
                      label: e.key,
                      pilih: ikon == e.key,
                      onTap: () => set(() => ikon = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _Judul('Fitur'),
              _Opsi(
                ikon: Icons.task_alt,
                judul: 'Ceklis lunas',
                sub: 'Tandai item yang sudah dibayar',
                on: lunas,
                onTap: () => set(() => lunas = !lunas),
              ),
              _Opsi(
                ikon: Icons.event_outlined,
                judul: 'Tenggat',
                sub: 'Tanggal jatuh tempo + pengingat',
                on: tenggat,
                onTap: () => set(() => tenggat = !tenggat),
              ),
              _Opsi(
                ikon: Icons.image_outlined,
                judul: 'Lampiran foto',
                sub: 'mis. bukti transfer',
                on: foto,
                onTap: () => set(() => foto = !foto),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target nominal (opsional)',
                  hintText: 'mis. 5jt, untuk tabungan',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (nama.text.trim().isNotEmpty) Navigator.pop(c, true);
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  final t = target.text.trim().isEmpty ? null : parseNominal(target.text);
  if (target.text.trim().isNotEmpty && (t == null || t <= 0)) {
    _toast(context, 'Target tidak valid');
    return null;
  }
  final data = {
    'nama': nama.text.trim(),
    'ikon': ikon,
    'pakai_tenggat': tenggat,
    'pakai_lunas': lunas,
    'pakai_foto': foto,
    'target': t,
  };
  try {
    return m == null
        ? await db.from('menu').insert(data).select().single()
        : await db
              .from('menu')
              .update(data)
              .eq('id', m['id'])
              .select()
              .single();
  } catch (e) {
    if (context.mounted) _toast(context, 'Gagal simpan: ${_pesan(e)}');
    return null;
  }
}

class _Judul extends StatelessWidget {
  final String t;
  const _Judul(this.t);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: C.muted,
      ),
    ),
  );
}

class _IkonTile extends StatelessWidget {
  final IconData ikon;
  final String label;
  final bool pilih;
  final VoidCallback onTap;
  const _IkonTile({
    required this.ikon,
    required this.label,
    required this.pilih,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: pilih,
    label: 'Ikon $label',
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: pilih ? C.btn : C.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: pilih ? C.btn : C.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, size: 24, color: pilih ? C.onBtn : C.text),
            const SizedBox(height: 6),
            Text(
              label[0].toUpperCase() + label.substring(1),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: pilih ? C.onBtn : C.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Opsi extends StatelessWidget {
  final IconData ikon;
  final String judul, sub;
  final bool on;
  final VoidCallback onTap;
  const _Opsi({
    required this.ikon,
    required this.judul,
    required this.sub,
    required this.on,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: C.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: on ? C.lime.withValues(alpha: 0.35) : C.track,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(ikon, size: 20, color: C.text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      judul,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: C.text,
                      ),
                    ),
                    Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
                  ],
                ),
              ),
              Switch(value: on, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    ),
  );
}

// ───────────────────────── Isi satu menu ─────────────────────────

class MenuPage extends StatefulWidget {
  final Row_ menu;
  const MenuPage({super.key, required this.menu});
  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late Row_ menu = widget.menu;
  List<Row_> items = [];
  bool loading = true;

  bool get pemilik => menu['user_id'] == _uid;
  int get id => (menu['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await db
          .from('menu_item')
          .select()
          .eq('menu_id', id)
          .order('lunas')
          .order('tanggal', ascending: false)
          .order('id', ascending: false);
      if (mounted) setState(() => items = r);
    } catch (e) {
      if (mounted) _toast(context, 'Gagal memuat: ${_pesan(e)}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _item([Row_? row]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ItemForm(menu: menu, row: row),
      ),
    );
    if (ok == true) await load();
  }

  Future<void> _toggleLunas(Row_ i) async {
    final jadiLunas = i['lunas'] != true;
    String? tipe; // null = tidak dicatat sebagai transaksi
    if (jadiLunas) {
      final pilih = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Tandai "${i['judul']}" lunas?'),
          content: const Text('Catat juga ke saldo sebagai transaksi?'),
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, 'keluar'),
              child: const Text('Ya, pengeluaran'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'masuk'),
              child: const Text('Ya, pemasukan'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'tidak'),
              child: const Text('Lunas saja'),
            ),
          ],
        ),
      );
      if (pilih == null) return;
      if (pilih != 'tidak') tipe = pilih;
    }
    setState(() => i['lunas'] = jadiLunas);
    try {
      await db.from('menu_item').update({'lunas': jadiLunas}).eq('id', i['id']);
      if (tipe != null) {
        await db.from('trx').insert({
          'toko': '${i['judul']} (${menu['nama']})',
          'kategori': 'tagihan',
          'tipe': tipe,
          'jumlah': i['nominal'],
          'tanggal': ymd(DateTime.now()),
        });
        if (mounted) _toast(context, 'Lunas & tercatat di transaksi');
      }
    } catch (e) {
      if (mounted) {
        setState(() => i['lunas'] = !jadiLunas);
        _toast(context, 'Gagal: ${_pesan(e)}');
      }
    }
    await load();
  }

  Future<void> _ubahMenu() async {
    final m = await formMenu(context, menu);
    if (m != null && mounted) setState(() => menu = m);
  }

  Future<void> _hapusMenu() async {
    final ok = await _konfirmasi(
      context,
      pemilik ? 'Hapus menu ini?' : 'Keluar dari menu ini?',
      pemilik
          ? 'Semua item dan foto di dalamnya ikut terhapus, juga untuk teman yang diundang.'
          : 'Kamu tidak bisa melihat menu ini lagi sampai diundang ulang.',
      pemilik ? 'Hapus' : 'Keluar',
    );
    if (!ok) return;
    try {
      if (pemilik) {
        final fotos = items.map((i) => i['foto']).whereType<String>().toList();
        if (fotos.isNotEmpty) await db.storage.from('lampiran').remove(fotos);
        await db.from('menu').delete().eq('id', id);
      } else {
        await db
            .from('menu_anggota')
            .delete()
            .eq('menu_id', id)
            .eq('user_id', _uid!);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast(context, 'Gagal: ${_pesan(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ringkasItem(items);
    final lunasOn = menu['pakai_lunas'] == true;
    final target = menu['target'] as num?;
    final p = target == null ? null : (s.total / target).clamp(0, 1).toDouble();
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        title: Text(
          '${menu['nama']}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Teman',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: C.bg,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              builder: (_) => _Anggota(menu: menu, pemilik: pemilik),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Lainnya',
            onSelected: (v) => v == 'ubah' ? _ubahMenu() : _hapusMenu(),
            itemBuilder: (_) => [
              if (pemilik)
                const PopupMenuItem(value: 'ubah', child: Text('Ubah menu')),
              PopupMenuItem(
                value: 'hapus',
                child: Text(pemilik ? 'Hapus menu' : 'Keluar dari menu'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.btn,
        foregroundColor: C.onBtn,
        onPressed: () => _item(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
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
                  Text(
                    lunasOn ? 'Belum lunas' : 'Total',
                    style: const TextStyle(color: Color(0xFF24361F)),
                  ),
                  AnimatedRp(
                    lunasOn ? s.sisa : s.total,
                    style: const TextStyle(
                      color: C.dark,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (lunasOn)
                    Text(
                      'Lunas ${rp(s.lunas)} dari ${rp(s.total)}',
                      style: const TextStyle(color: Color(0xFF24361F)),
                    ),
                  if (p != null) ...[
                    const SizedBox(height: 10),
                    AnimatedBar(value: p, color: C.dark),
                    const SizedBox(height: 6),
                    Text(
                      '${(p * 100).floor()}% dari target ${rp(target!)}',
                      style: const TextStyle(
                        color: Color(0xFF24361F),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: TypingDots(color: C.green)),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Belum ada isi. Ketuk Tambah, atau sebut nama menu ini saat '
                  'mengetik di tombol + Beranda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted),
                ),
              )
            else
              for (final (n, i) in items.indexed)
                FadeIn(
                  key: ValueKey(i['id']),
                  index: n,
                  child: _ItemTile(
                    item: i,
                    menu: menu,
                    onTap: () => _item(i),
                    onCek: lunasOn ? () => _toggleLunas(i) : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final Row_ item, menu;
  final VoidCallback onTap;
  final VoidCallback? onCek;
  const _ItemTile({
    required this.item,
    required this.menu,
    required this.onTap,
    this.onCek,
  });
  @override
  Widget build(BuildContext context) {
    final lunas = item['lunas'] == true;
    final tenggat = menu['pakai_tenggat'] == true ? item['tenggat'] : null;
    final telat =
        tenggat != null &&
        !lunas &&
        (DateTime.tryParse('$tenggat')
                ?.isBefore(DateTime.now().subtract(const Duration(days: 1))) ??
            false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: C.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
            child: Row(
              children: [
                if (onCek != null)
                  IconButton(
                    tooltip: lunas ? 'Batalkan lunas' : 'Tandai lunas',
                    onPressed: onCek,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        lunas
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        key: ValueKey(lunas),
                        color: lunas ? C.green : C.muted,
                        size: 28,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['judul']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: lunas ? TextDecoration.lineThrough : null,
                          color: lunas ? C.muted : C.text,
                        ),
                      ),
                      Text(
                        [
                          '${item['tanggal']}',
                          if (tenggat != null) 'tempo $tenggat',
                          if ((item['deskripsi'] ?? '').toString().isNotEmpty)
                            '${item['deskripsi']}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: telat ? C.expense : C.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item['foto'] != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.image_outlined, size: 18, color: C.muted),
                  ),
                Text(
                  rp(item['nominal'] as num),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: lunas ? C.muted : C.text,
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

Future<bool> _konfirmasi(
  BuildContext context,
  String judul,
  String isi,
  String aksi,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(aksi),
          ),
        ],
      ),
    ) ==
    true;

// ───────────────────────── Teman di menu ─────────────────────────

class _Anggota extends StatefulWidget {
  final Row_ menu;
  final bool pemilik;
  const _Anggota({required this.menu, required this.pemilik});
  @override
  State<_Anggota> createState() => _AnggotaState();
}

class _AnggotaState extends State<_Anggota> {
  final kode = TextEditingController();
  List<Row_> rows = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await db
          .from('menu_anggota')
          .select()
          .eq('menu_id', widget.menu['id']);
      if (mounted) setState(() => rows = r);
    } catch (_) {}
  }

  Future<void> _tambah() async {
    if (kode.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final e = await db.rpc(
        'tambah_anggota',
        params: {'p_menu': widget.menu['id'], 'p_kode': kode.text},
      );
      kode.clear();
      if (mounted) _toast(context, '${e ?? 'Teman'} ditambahkan');
      await _load();
    } catch (e) {
      if (mounted) _toast(context, _pesan(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _keluarkan(Row_ a) async {
    try {
      await db
          .from('menu_anggota')
          .delete()
          .eq('menu_id', widget.menu['id'])
          .eq('user_id', a['user_id']);
      await _load();
    } catch (e) {
      if (mounted) _toast(context, 'Gagal: ${_pesan(e)}');
    }
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Teman di menu ini',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Teman yang diundang bisa melihat, menambah, dan mencentang isi menu ini.',
            style: TextStyle(color: C.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (widget.pemilik)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: kode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Kode teman',
                      hintText: 'mis. 4F9A21BC',
                    ),
                    onSubmitted: (_) => _tambah(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  // Tema membuat tombol selebar layar; di dalam Row harus dibatasi.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: busy ? null : _tambah,
                  child: const Text('Undang'),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Belum ada teman.', style: TextStyle(color: C.muted)),
            )
          else
            for (final a in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text('${a['email'] ?? 'Teman'}'),
                trailing: widget.pemilik
                    ? IconButton(
                        tooltip: 'Keluarkan',
                        icon: const Icon(Icons.close),
                        onPressed: () => _keluarkan(a),
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}

// ───────────────────────── Form item ─────────────────────────

class ItemForm extends StatefulWidget {
  final Row_ menu;
  final Row_? row;

  /// Isian awal dari AI: {judul, nominal}.
  final Row_? awal;
  const ItemForm({super.key, required this.menu, this.row, this.awal});
  @override
  State<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<ItemForm> {
  late final r = widget.row ?? widget.awal ?? const {};
  late final judul = TextEditingController(text: r['judul'] ?? '');
  late final nominal = TextEditingController(
    text: r['nominal'] == null ? '' : '${r['nominal']}',
  );
  late final deskripsi = TextEditingController(text: r['deskripsi'] ?? '');
  late DateTime tanggal =
      DateTime.tryParse('${r['tanggal']}') ?? DateTime.now();
  late DateTime? tenggat = DateTime.tryParse('${r['tenggat']}');
  late bool lunas = r['lunas'] == true;
  late String? foto = r['foto'];
  XFile? fotoBaru;
  String? fotoUrl;
  bool busy = false;

  Row_ get m => widget.menu;

  @override
  void initState() {
    super.initState();
    if (foto != null) _urlFoto();
  }

  Future<void> _urlFoto() async {
    try {
      final u = await db.storage.from('lampiran').createSignedUrl(foto!, 3600);
      if (mounted) setState(() => fotoUrl = u);
    } catch (_) {}
  }

  Future<void> _pilihFoto(ImageSource src) async {
    final f = await ImagePicker().pickImage(
      source: src,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (f != null) setState(() => fotoBaru = f);
  }

  Future<DateTime?> _tgl(DateTime awal) => showDatePicker(
    context: context,
    initialDate: awal,
    firstDate: DateTime(2000),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );

  Future<void> _save() async {
    final n = parseNominal(nominal.text) ?? 0;
    if (judul.text.trim().isEmpty) return _toast(context, 'Isi judulnya');
    setState(() => busy = true);
    try {
      String? path = foto;
      if (fotoBaru != null) {
        var bytes = await fotoBaru!.readAsBytes();
        var e = fotoBaru!.name.split('.').last.toLowerCase();
        try {
          bytes = await keWebp(bytes);
          e = 'webp';
        } catch (_) {
          // Gagal konversi (mis. browser lama): unggah file aslinya.
          if (!['png', 'webp', 'heic'].contains(e)) e = 'jpg';
        }
        path = '${m['id']}/${DateTime.now().microsecondsSinceEpoch}.$e';
        await db.storage
            .from('lampiran')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: 'image/$e'),
            );
        if (foto != null) await db.storage.from('lampiran').remove([foto!]);
      }
      final data = {
        'menu_id': m['id'],
        'judul': judul.text.trim(),
        'nominal': n,
        'deskripsi': deskripsi.text.trim().isEmpty
            ? null
            : deskripsi.text.trim(),
        'tanggal': ymd(tanggal),
        'tenggat': tenggat == null ? null : ymd(tenggat!),
        'lunas': lunas,
        'foto': path,
      };
      widget.row == null
          ? await db.from('menu_item').insert(data)
          : await db.from('menu_item').update(data).eq('id', widget.row!['id']);
    } catch (e) {
      // Form tetap terbuka supaya isian tidak hilang.
      if (mounted) {
        setState(() => busy = false);
        _toast(context, 'Gagal simpan: ${_pesan(e)}');
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _hapus() async {
    if (!await _konfirmasi(context, 'Hapus item ini?', '', 'Hapus')) return;
    setState(() => busy = true);
    try {
      await db.from('menu_item').delete().eq('id', widget.row!['id']);
      if (foto != null) await db.storage.from('lampiran').remove([foto!]);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        _toast(context, 'Gagal hapus: ${_pesan(e)}');
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
          '${m['nama']}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (widget.row != null)
            IconButton(
              tooltip: 'Hapus',
              onPressed: busy ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nominal,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: judul,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Judul'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: deskripsi,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Deskripsi (opsional)',
            ),
          ),
          const SizedBox(height: 12),
          _Pilih(
            judul: 'Tanggal',
            isi: ymd(tanggal),
            ikon: Icons.calendar_today,
            onTap: () async {
              final d = await _tgl(tanggal);
              if (d != null) setState(() => tanggal = d);
            },
          ),
          if (m['pakai_tenggat'] == true) ...[
            const SizedBox(height: 8),
            _Pilih(
              judul: 'Tenggat',
              isi: tenggat == null ? 'Tidak ada' : ymd(tenggat!),
              ikon: Icons.event_outlined,
              onTap: () async {
                final d = await _tgl(tenggat ?? DateTime.now());
                if (d != null) setState(() => tenggat = d);
              },
              onClear: tenggat == null
                  ? null
                  : () => setState(() => tenggat = null),
            ),
          ],
          if (m['pakai_lunas'] == true) ...[
            const SizedBox(height: 8),
            Material(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
              child: SwitchListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                value: lunas,
                onChanged: (v) => setState(() => lunas = v),
                title: const Text('Sudah lunas'),
              ),
            ),
          ],
          if (m['pakai_foto'] == true) ...[
            const SizedBox(height: 12),
            if (fotoBaru != null || fotoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: fotoBaru != null
                    ? FutureBuilder(
                        future: fotoBaru!.readAsBytes(),
                        builder: (_, s) => s.hasData
                            ? Image.memory(
                                s.data!,
                                height: 220,
                                fit: BoxFit.cover,
                              )
                            : const SizedBox(height: 220),
                      )
                    : Image.network(fotoUrl!, height: 220, fit: BoxFit.cover),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pilihFoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Kamera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pilihFoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Galeri'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : _save,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

class _Pilih extends StatelessWidget {
  final String judul, isi;
  final IconData ikon;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _Pilih({
    required this.judul,
    required this.isi,
    required this.ikon,
    required this.onTap,
    this.onClear,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: C.card,
    borderRadius: BorderRadius.circular(16),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(judul),
      subtitle: Text(isi),
      trailing: onClear == null
          ? Icon(ikon)
          : IconButton(
              tooltip: 'Hapus $judul',
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
      onTap: onTap,
    ),
  );
}
