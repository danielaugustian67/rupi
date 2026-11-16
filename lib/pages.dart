import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'akun.dart';
import 'anim.dart';
import 'chat.dart';
import 'form_page.dart';
import 'kunci.dart';
import 'format.dart';
import 'laporan.dart';
import 'main.dart' show db, LoginPage;
import 'receipt.dart' show parseWithAi;
import 'rutin.dart';
import 'notif.dart';
import 'menu.dart';
import 'theme.dart';
import 'tutorial.dart';

typedef Trx = Map<String, dynamic>;

/// Kerangka aplikasi: memegang data bulan aktif + bottom nav.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int tab = 0;
  DateTime bulan = DateTime(DateTime.now().year, DateTime.now().month);
  List<Trx> rows = [];
  Map<String, int> anggaran = {}; // kategori -> batas per bulan
  List<Map<String, dynamic>> akun = []; // kartu saldo (+ saldo dari view)
  bool loading = true;
  bool terkunci = false;
  DateTime? _sembunyi;
  late final AppLifecycleListener _siklus;

  static final _android =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    kunciAktif().then((on) {
      if (on && mounted) _kunci();
    });
    // Kunci lagi kalau app ditinggal di background lebih dari 1 menit.
    _siklus = AppLifecycleListener(
      onHide: () => _sembunyi = DateTime.now(),
      onShow: () async {
        final t = _sembunyi;
        if (t != null &&
            DateTime.now().difference(t).inSeconds > 60 &&
            await kunciAktif()) {
          _kunci();
        }
      },
    );
    if (_android) {
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_dariWidget);
      HomeWidget.widgetClicked.listen(_dariWidget);
    }
    load();
    // Izin notifikasi ditanya setelah panduan, supaya dialognya tidak menutupi.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await tutorialPertamaKali(context);
      _pengingat();
    });
  }

  @override
  void dispose() {
    _siklus.dispose();
    super.dispose();
  }

  void _dariWidget(Uri? u) {
    if (u?.host == 'tambah' && mounted) openTambah();
  }

  Future<void> _kunci() async {
    setState(() => terkunci = true);
    if (await verifikasi() && mounted) setState(() => terkunci = false);
  }

  /// Widget layar utama (Android) & notifikasi ringkasan ikut data bulan ini.
  Future<void> _perbaruiLuar() async {
    final now = DateTime.now();
    if (kIsWeb || bulan.year != now.year || bulan.month != now.month) return;
    final masuk = sum('masuk'), keluar = sum('keluar');
    final kat = keluarPerKategori(rows);
    try {
      await jadwalRingkasan(
        bulan,
        masuk,
        keluar,
        kat.isEmpty ? null : '${kat.first.key} ${rp(kat.first.value)}',
      );
      if (_android) {
        await HomeWidget.saveWidgetData(
          'judul',
          'Saldo ${namaBulan[bulan.month - 1]}',
        );
        await HomeWidget.saveWidgetData('saldo', rp(masuk - keluar));
        await HomeWidget.saveWidgetData(
          'rincian',
          '▲ ${rp(masuk)}   ▼ ${rp(keluar)}',
        );
        await HomeWidget.updateWidget(androidName: 'RupiWidget');
      }
    } catch (_) {} // widget/notifikasi opsional
  }

  Future<void> load() async {
    try {
      await db.rpc('jalankan_rutin'); // catat transaksi rutin yang jatuh tempo
      final r = await db
          .from('trx')
          .select()
          .gte('tanggal', ymd(bulan))
          .lt('tanggal', ymd(DateTime(bulan.year, bulan.month + 1)))
          .order('tanggal', ascending: false)
          .order('id', ascending: false);
      final a = await db.from('anggaran').select('kategori,batas');
      final k = await db
          .from('akun_v')
          .select()
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          rows = r;
          akun = k;
          anggaran = {
            for (final x in a) '${x['kategori']}': (x['batas'] as num).toInt(),
          };
        });
        _perbaruiLuar();
      }
    } catch (e) {
      _toast('Gagal memuat: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Izin notifikasi + jadwal pengingat harian & jatuh tempo pinjaman.
  Future<void> _pengingat() async {
    if (kIsWeb) return; // notifikasi lokal tidak ada di browser
    try {
      await initNotif();
      // Item menu bertenggat yang belum lunas.
      final p = await db
          .from('menu_item')
          .select('id,judul,nominal,tenggat,menu!inner(pakai_tenggat)')
          .eq('lunas', false)
          .eq('menu.pakai_tenggat', true)
          .not('tenggat', 'is', null);
      await jadwalTempo(p);
    } catch (_) {
      // Notifikasi opsional; app tetap jalan tanpa izin.
    }
  }

  Future<void> setAnggaran(String kategori, int? batas) async {
    try {
      batas == null
          ? await db.from('anggaran').delete().eq('kategori', kategori)
          : await db.from('anggaran').upsert({
              'kategori': kategori,
              'batas': batas,
            }, onConflict: 'user_id,kategori');
      await load();
    } catch (e) {
      _toast('Gagal simpan anggaran: $e');
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void gantiBulan(int d) {
    setState(() {
      bulan = DateTime(bulan.year, bulan.month + d);
      loading = true;
    });
    load();
  }

  Future<void> openForm({
    String tipe = 'keluar',
    Trx? row,
    String source = '',
    bool isReceipt = false,
    Map<String, dynamic>? ai,
  }) async {
    if (row?['transfer'] != null) {
      if (await hapusTransfer(context, row!)) load();
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FormPage(
          tipe: tipe,
          row: row,
          sourceText: source,
          isReceipt: isReceipt,
          ai: ai,
          akun: akun,
        ),
      ),
    );
    if (changed == true) load();
  }

  /// Teks bebas / hasil scan: proses AI dulu, baru buka form yang sudah terisi.
  /// AI mati/gagal -> tetap buka form biasa dengan tebakan tanpa AI.
  Future<void> prosesTeks(String src, {bool isReceipt = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TypingDots(color: C.green, size: 10),
                  SizedBox(height: 14),
                  Text('AI sedang membaca'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final ai = await parseWithAi(src);
    if (!mounted) return;
    Navigator.pop(context);
    if (ai == null) {
      _toast('AI sedang tidak tersedia, silakan cek & isi manual');
    }
    // AI mengenali salah satu menu custom: langsung isi item di menu itu.
    if (ai?['jenis'] == 'menu' && ai?['menu_id'] is num) {
      try {
        final m = await db
            .from('menu')
            .select()
            .eq('id', ai!['menu_id'])
            .maybeSingle();
        if (m != null && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItemForm(
                menu: m,
                awal: {
                  'judul': ai['toko'] ?? src,
                  'nominal': (ai['total'] as num?)?.round(),
                },
              ),
            ),
          );
          return;
        }
      } catch (_) {} // gagal ambil menu: lanjut sebagai transaksi biasa
    }
    if (!mounted) return;
    await openForm(source: src, isReceipt: isReceipt, ai: ai);
  }

  Future<void> scan(ImageSource src) async {
    final img = await ImagePicker().pickImage(source: src, maxWidth: 1600);
    if (img == null) return;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = (await recognizer.processImage(
        InputImage.fromFilePath(img.path),
      )).text;
      if (!mounted) return;
      if (text.trim().isEmpty) {
        return _toast('Teks struk tidak terbaca, coba foto lebih terang');
      }
      await prosesTeks(text, isReceipt: true);
    } finally {
      await recognizer.close();
    }
  }

  Future<void> logout() async {
    await db.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  void openTambah() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (c) => TambahSheet(
        onText: (t) {
          Navigator.pop(c);
          prosesTeks(t);
        },
        onCamera: () {
          Navigator.pop(c);
          scan(ImageSource.camera);
        },
        onGallery: () {
          Navigator.pop(c);
          scan(ImageSource.gallery);
        },
        onManual: () {
          Navigator.pop(c);
          openForm();
        },
        onTransfer: () async {
          Navigator.pop(c);
          if (await formTransfer(context, akun)) load();
        },
        onMenu: () {
          Navigator.pop(c);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MenuListPage()),
          );
        },
      ),
    );
  }

  /// Kategori yang anggarannya hampir habis / terlewati bulan ini.
  List<String> peringatanAnggaran() {
    final pakai = {for (final e in keluarPerKategori(rows)) e.key: e.value};
    return [
      for (final e in anggaran.entries)
        if (statusAnggaran(pakai[e.key] ?? 0, e.value) case final st
            when st != 'aman')
          st == 'lewat'
              ? 'Anggaran ${e.key} terlewati: ${rp(pakai[e.key]!)} dari ${rp(e.value)}'
              : 'Anggaran ${e.key} hampir habis: sisa ${rp(e.value - pakai[e.key]!)}',
    ];
  }

  /// Total bulan ini per tipe; [akunId] membatasi ke satu kartu.
  int sum(String tipe, [Object? akunId]) => rows
      .where((r) => r['tipe'] == tipe && r['transfer'] == null)
      .where((r) => akunId == null || r['akun_id'] == akunId)
      .fold(0, (s, r) => s + (r['jumlah'] as num).toInt());

  @override
  Widget build(BuildContext context) {
    final pages = [
      BerandaPage(shell: this),
      TransaksiPage(shell: this),
      const SizedBox(),
      LaporanPage(shell: this),
      const ChatPage(),
    ];
    return Stack(
      children: [
        Scaffold(
          body: pages[tab],
          bottomNavigationBar: _BottomNav(
            index: tab,
            onTap: (i) => i == 2 ? openTambah() : setState(() => tab = i),
          ),
        ),
        if (terkunci)
          Positioned.fill(
            child: LayarKunci(
              onBuka: _kunci,
              onLogout: () async {
                await setKunci(false);
                logout();
              },
            ),
          ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});

  static const items = [
    (Icons.home_outlined, 'Beranda'),
    (Icons.format_list_bulleted, 'Transaksi'),
    (Icons.add, 'Tambah transaksi'),
    (Icons.bar_chart_rounded, 'Laporan'),
    (Icons.chat_bubble_outline, 'Chat AI'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: C.card,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < items.length; i++)
                Semantics(
                  label: items[i].$2,
                  selected: i == index,
                  button: true,
                  child: InkResponse(
                    onTap: () => onTap(i),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == 2
                            ? C.green
                            : (i == index ? C.btn : Colors.transparent),
                      ),
                      child: Icon(
                        items[i].$1,
                        color: i == 2
                            ? Colors.white
                            : (i == index ? C.onBtn : C.muted),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BerandaPage extends StatefulWidget {
  final ShellState shell;
  const BerandaPage({super.key, required this.shell});
  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  bool hide = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.shell;
    final email = db.auth.currentUser?.email ?? '';
    final nama = email.isEmpty ? '' : email.split('@').first;
    final namaCap = nama.isEmpty
        ? 'kamu'
        : nama[0].toUpperCase() + nama.substring(1);
    final jam = DateTime.now().hour;
    final salam = jam < 11
        ? 'Selamat pagi,'
        : jam < 15
        ? 'Selamat siang,'
        : jam < 19
        ? 'Selamat sore,'
        : 'Selamat malam,';
    String uang(int v) => hide ? 'Rp•••••' : rp(v);

    return RefreshIndicator(
      onRefresh: s.load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GlowBox(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 23,
                          backgroundColor: C.lime,
                          child: Text(
                            namaCap[0].toUpperCase(),
                            style: const TextStyle(
                              color: C.dark,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                salam,
                                style: const TextStyle(
                                  color: Color(0xFFB8C4B5),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                namaCap,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _GlassButton(
                          icon: Icons.help_outline,
                          label: 'Panduan',
                          onTap: () => bukaTutorial(context),
                        ),
                        const SizedBox(width: 8),
                        _GlassButton(
                          icon: C.gelap
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                          label: 'Tampilan',
                          onTap: () => pilihTema(context),
                        ),
                        const SizedBox(width: 8),
                        _GlassButton(
                          icon: Icons.logout,
                          label: 'Keluar akun',
                          onTap: s.logout,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _KartuPager(
                      shell: s,
                      bulan: namaBulan[s.bulan.month - 1],
                      hide: hide,
                      uang: uang,
                      onToggle: () => setState(() => hide = !hide),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        _Action(
                          'Pemasukan',
                          Icons.south_west,
                          const Color(0x2970BE5A),
                          () => s.openForm(tipe: 'masuk'),
                        ),
                        const SizedBox(width: 10),
                        _Action(
                          'Pengeluaran',
                          Icons.north_east,
                          const Color(0x24DC965A),
                          () => s.openForm(tipe: 'keluar'),
                        ),
                        const SizedBox(width: 10),
                        // ML Kit (OCR) hanya ada di Android/iOS.
                        if (!kIsWeb) ...[
                          _Action(
                            'Scan struk',
                            Icons.document_scanner_outlined,
                            const Color(0x245AA0BE),
                            () => s.scan(ImageSource.camera),
                          ),
                          const SizedBox(width: 10),
                        ],
                        _Action(
                          'Menu',
                          Icons.dashboard_customize_outlined,
                          // Selalu di atas latar glow gelap, jadi tetap terang di kedua mode.
                          const Color(0xFFF3F5F1),
                          () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MenuListPage(),
                              ),
                            );
                            s.load(); // tandai lunas bisa menambah transaksi
                          },
                          dark: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -14),
            child: Container(
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                children: [
                  for (final w in s.peringatanAnggaran())
                    FadeIn(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBE6D9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: C.expense),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                w,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Transaksi terakhir',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => s.setState(() => s.tab = 1),
                              child: Text(
                                'Lihat semua',
                                style: TextStyle(
                                  color: C.income,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (s.loading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: TypingDots(color: C.green)),
                          )
                        else if (s.rows.isEmpty)
                          const _Empty()
                        else
                          for (final r in s.rows.take(5))
                            TrxTile(
                              row: r,
                              onTap: () => s.openForm(row: r),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransaksiPage extends StatefulWidget {
  final ShellState shell;
  const TransaksiPage({super.key, required this.shell});
  @override
  State<TransaksiPage> createState() => _TransaksiPageState();
}

class _TransaksiPageState extends State<TransaksiPage> {
  String filter = 'semua';
  String q = '';
  String? kat; // null = semua kategori
  Object? kartu; // null = semua kartu

  @override
  Widget build(BuildContext context) {
    final s = widget.shell;
    final shown = s.rows.where((r) {
      if (filter != 'semua' && r['tipe'] != filter) return false;
      if (kat != null && r['kategori'] != kat) return false;
      if (kartu != null && r['akun_id'] != kartu) return false;
      if (q.isEmpty) return true;
      final hay = '${r['toko']} ${r['kategori']}'.toLowerCase();
      return hay.contains(q.toLowerCase());
    }).toList();
    final byDay = <String, List<Trx>>{};
    for (final r in shown) {
      byDay.putIfAbsent('${r['tanggal']}', () => []).add(r);
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: s.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Transaksi',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Transaksi rutin',
                  icon: const Icon(Icons.repeat),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RutinPage()),
                    );
                    s.load();
                  },
                ),
                BulanSwitcher(shell: s),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                hintText: 'Cari transaksi',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('semua', 'Semua'),
                  ('masuk', '▲ Masuk'),
                  ('keluar', '▼ Keluar'),
                ])
                  ChoiceChip(
                    label: Text(f.$2),
                    selected: filter == f.$1,
                    showCheckmark: false,
                    selectedColor: C.btn,
                    backgroundColor: C.card,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(
                      color: filter == f.$1 ? C.onBtn : C.text,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => filter = f.$1),
                  ),
                _Saring<String>(
                  label: kat == null ? 'Kategori' : kat!,
                  aktif: kat != null,
                  pilihan: {
                    for (final k in [...kategoriList, 'transfer']) k: k,
                  },
                  onPilih: (v) => setState(() => kat = v),
                ),
                if (s.akun.isNotEmpty)
                  _Saring<Object>(
                    label: kartu == null
                        ? 'Kartu'
                        : '${s.akun.firstWhere((a) => a['id'] == kartu, orElse: () => {'nama': 'Kartu'})['nama']}',
                    aktif: kartu != null,
                    pilihan: {for (final a in s.akun) a['id']: '${a['nama']}'},
                    onPilih: (v) => setState(() => kartu = v),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (s.loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: TypingDots(color: C.green)),
              )
            else if (byDay.isEmpty)
              const _Card(child: _Empty())
            else
              for (final e in byDay.entries) ...[
                _Card(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _labelHari(e.key),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            _subtotal(e.value),
                            style: TextStyle(
                              color: C.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      for (final r in e.value)
                        TrxTile(
                          row: r,
                          onTap: () => s.openForm(row: r),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  String _labelHari(String tgl) {
    final d = DateTime.tryParse(tgl);
    if (d == null) return tgl;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    return '${d.day} ${namaBulan[d.month - 1]}';
  }

  String _subtotal(List<Trx> rs) {
    final net = rs.fold<int>(0, (s, r) {
      final v = (r['jumlah'] as num).toInt();
      return s + (r['tipe'] == 'masuk' ? v : -v);
    });
    return '${net >= 0 ? '▲' : '▼'} ${rp(net.abs())}';
  }
}

/// Sheet "Tambah": ketik bebas + pilihan input.
class TambahSheet extends StatefulWidget {
  final ValueChanged<String> onText;
  final VoidCallback onCamera, onGallery, onManual, onMenu, onTransfer;
  const TambahSheet({
    required this.onTransfer,
    super.key,
    required this.onText,
    required this.onCamera,
    required this.onGallery,
    required this.onManual,
    required this.onMenu,
  });
  @override
  State<TambahSheet> createState() => _TambahSheetState();
}

class _TambahSheetState extends State<TambahSheet> {
  final ctrl = TextEditingController();
  final _suara = SpeechToText();
  bool dengar = false;

  @override
  void dispose() {
    _suara.cancel();
    super.dispose();
  }

  /// Ucapkan transaksi, hasilnya masuk kotak teks.
  Future<void> _mic() async {
    if (dengar) {
      await _suara.stop();
      return setState(() => dengar = false);
    }
    final ok = await _suara.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) {
          setState(() => dengar = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => dengar = false);
      },
    );
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mikrofon tidak tersedia atau izin ditolak'),
          ),
        );
      }
      return;
    }
    setState(() => dengar = true);
    await _suara.listen(
      localeId: 'id_ID',
      listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation),
      onResult: (r) => setState(() {
        ctrl.text = r.recognizedWords;
        ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      }),
    );
  }

  void _kirim() {
    final t = ctrl.text.trim();
    if (t.isNotEmpty) widget.onText(t);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFC9CDC6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tambah',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: limeCard,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ketik bebas, AI yang isi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: C.dark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    decoration: BoxDecoration(
                      color: C.card,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            autofocus: false,
                            // iOS inline prediction menandai huruf awal (terlihat terblok).
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _kirim(),
                            decoration: const InputDecoration(
                              hintText: 'Ketik jumlah & keterangan',
                              filled: false,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: dengar ? 'Berhenti merekam' : 'Bicara',
                          onPressed: _mic,
                          icon: dengar
                              ? TypingDots(color: C.expense, size: 6)
                              : const Icon(Icons.mic_none, color: C.dark),
                        ),
                        IconButton.filled(
                          tooltip: 'Kirim',
                          style: IconButton.styleFrom(
                            backgroundColor: C.dark,
                            minimumSize: const Size(44, 44),
                          ),
                          onPressed: _kirim,
                          icon: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                if (!kIsWeb) ...[
                  _Opt(
                    'Scan struk',
                    'Total terisi otomatis',
                    Icons.document_scanner_outlined,
                    widget.onCamera,
                    dark: true,
                  ),
                  _Opt(
                    'Dari galeri',
                    'Foto struk yang ada',
                    Icons.photo_outlined,
                    widget.onGallery,
                  ),
                ],
                _Opt(
                  'Manual',
                  'Isi form sendiri',
                  Icons.edit_outlined,
                  widget.onManual,
                ),
                _Opt(
                  'Menu',
                  'Bill, tabungan, dll',
                  Icons.dashboard_customize_outlined,
                  widget.onMenu,
                ),
                _Opt(
                  'Transfer',
                  'Antar kartu',
                  Icons.swap_horiz,
                  widget.onTransfer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TrxTile extends StatelessWidget {
  final Trx row;
  final VoidCallback onTap;
  const TrxTile({super.key, required this.row, required this.onTap});

  static const _bg = {
    'makan': Color(0xFFFBE6D9),
    'transport': Color(0xFFE4ECF7),
    'belanja': Color(0xFFF5EDCF),
    'gaji': Color(0xFFDDF3D2),
    'tagihan': Color(0xFFECE6F5),
    'hiburan': Color(0xFFF7E1E8),
    'kesehatan': Color(0xFFDDF0EE),
    'transfer': Color(0xFFE6EBEA),
  };

  @override
  Widget build(BuildContext context) {
    final masuk = row['tipe'] == 'masuk';
    final kat = '${row['kategori']}';
    final ini = kat.length >= 2 ? kat[0].toUpperCase() + kat[1] : '?';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: C.line)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _bg[kat] ?? C.track,
              child: Text(
                ini,
                style: TextStyle(
                  color: _bg[kat] != null ? C.dark : C.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['toko']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(kat, style: TextStyle(color: C.muted, fontSize: 12)),
                ],
              ),
            ),
            Text(
              '${masuk ? '▲' : '▼'} ${rp(row['jumlah'] as num)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: masuk ? C.income : C.expense,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pemilih bulan aktif, dipakai Transaksi & Laporan.
class BulanSwitcher extends StatelessWidget {
  final ShellState shell;
  const BulanSwitcher({super.key, required this.shell});
  @override
  Widget build(BuildContext context) {
    final s = shell;
    return Container(
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE1D9)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Bulan sebelumnya',
            onPressed: () => s.gantiBulan(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '${namaBulan[s.bulan.month - 1].substring(0, 3)} ${s.bulan.year}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          IconButton(
            tooltip: 'Bulan berikutnya',
            onPressed: () => s.gantiBulan(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class SegeraPage extends StatelessWidget {
  final String judul;
  const SegeraPage({super.key, required this.judul});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              judul,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            Expanded(
              child: Center(
                child: Text('Segera hadir', style: TextStyle(color: C.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    decoration: BoxDecoration(
      color: C.card,
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(
        'Belum ada transaksi. Tekan + untuk mencatat.',
        style: TextStyle(color: C.muted),
      ),
    ),
  );
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    style: IconButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      minimumSize: const Size(46, 46),
    ),
    icon: Icon(icon, color: Colors.white, size: 20),
  );
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final VoidCallback onTap;
  final bool dark;
  const _Action(
    this.label,
    this.icon,
    this.bg,
    this.onTap, {
    this.dark = false,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: dark
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Icon(icon, color: dark ? C.dark : Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFD7E0D4), fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _Opt extends StatelessWidget {
  final String title, sub;
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;
  const _Opt(this.title, this.sub, this.icon, this.onTap, {this.dark = false});
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.5 : 1,
    child: Material(
      color: C.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: dark ? C.dark : const Color(0xFFDDF3D2),
                child: Icon(
                  icon,
                  size: 20,
                  color: dark ? Colors.white : C.dark,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: C.muted, fontSize: 12),
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

/// Kartu saldo bergaya kartu bank (lime, chip, logo).
class _BankCard extends StatelessWidget {
  final String judul, pojok, saldo, masuk, keluar;
  final int saldoNum;
  final bool hidden;
  static const _saldoStyle = TextStyle(
    color: Colors.white,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );
  final VoidCallback onToggle;
  final VoidCallback? onEdit;
  const _BankCard({
    this.onEdit,
    required this.judul,
    this.pojok = 'RUPI',
    required this.saldo,
    required this.saldoNum,
    required this.masuk,
    required this.keluar,
    required this.hidden,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    const soft = Color(0xFFD7E0D4);
    // Efek kaca: blur latar di belakang kartu + lapisan putih transparan.
    return AspectRatio(
      aspectRatio: 1.62,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.20),
                  C.lime.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Lingkaran dekoratif, khas kartu bank.
                Positioned(
                  right: -60,
                  top: -70,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                Positioned(
                  right: 30,
                  bottom: -90,
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ink.withValues(alpha: 0.08),
                        width: 18,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              judul,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: soft,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (onEdit != null)
                            IconButton(
                              tooltip: 'Ubah kartu',
                              onPressed: onEdit,
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: ink,
                                size: 20,
                              ),
                            ),
                          IconButton(
                            tooltip: hidden
                                ? 'Tampilkan saldo'
                                : 'Sembunyikan saldo',
                            onPressed: onToggle,
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: ink,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const _Chip(),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: hidden
                            ? Text(saldo, style: _saldoStyle)
                            : AnimatedRp(saldoNum, style: _saldoStyle),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _CardStat('▲ Masuk', masuk),
                          const SizedBox(width: 18),
                          _CardStat('▼ Keluar', keluar),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              pojok.toUpperCase(),
                              style: const TextStyle(
                                color: ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _CardStat extends StatelessWidget {
  final String label, value;
  const _CardStat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFFD7E0D4), fontSize: 11),
      ),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

/// Chip kartu (gambar sederhana, tanpa aset).
class _Chip extends StatelessWidget {
  const _Chip();
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 30,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      gradient: const LinearGradient(
        colors: [Color(0xFFE9D9A0), Color(0xFFC9B26A)],
      ),
    ),
    child: CustomPaint(painter: _ChipLines()),
  );
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 1;
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), p);
    canvas.drawLine(Offset(0, h * 2 / 3), Offset(w, h * 2 / 3), p);
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Sheet pilihan tampilan: Terang / Gelap / Ikut sistem.
void pilihTema(BuildContext context) {
  const opsi = [
    (ThemeMode.light, Icons.light_mode_outlined, 'Terang'),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Gelap'),
    (ThemeMode.system, Icons.brightness_auto_outlined, 'Ikut sistem'),
  ];
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.card,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Tampilan',
            style: TextStyle(
              color: C.text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          for (final (m, ic, label) in opsi)
            ListTile(
              leading: Icon(ic, color: C.text),
              title: Text(label, style: TextStyle(color: C.text)),
              trailing: temaMode.value == m
                  ? Icon(Icons.check_circle, color: C.income)
                  : null,
              onTap: () {
                setTema(m);
                Navigator.pop(ctx);
              },
            ),
          if (!kIsWeb) const _SwitchKunci(),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Kartu saldo yang bisa digeser: Total bulan ini, tiap kartu akun, lalu "+ Tambah kartu".
class _KartuPager extends StatefulWidget {
  final ShellState shell;
  final String bulan;
  final bool hide;
  final String Function(int) uang;
  final VoidCallback onToggle;
  const _KartuPager({
    required this.shell,
    required this.bulan,
    required this.hide,
    required this.uang,
    required this.onToggle,
  });
  @override
  State<_KartuPager> createState() => _KartuPagerState();
}

class _KartuPagerState extends State<_KartuPager> {
  final ctrl = PageController();
  int i = 0;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _form([Map<String, dynamic>? a]) async {
    if (await formAkun(context, a)) await widget.shell.load();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shell;
    final uang = widget.uang;
    final masuk = s.sum('masuk'), keluar = s.sum('keluar');
    final pages = <Widget>[
      _BankCard(
        judul: 'Total saldo · ${widget.bulan}',
        saldo: uang(masuk - keluar),
        saldoNum: masuk - keluar,
        masuk: uang(masuk),
        keluar: uang(keluar),
        hidden: widget.hide,
        onToggle: widget.onToggle,
      ),
      for (final a in s.akun)
        _BankCard(
          onEdit: () => _form(a),
          judul: '${a['nama']}',
          pojok: '${a['nama']}',
          saldo: uang((a['saldo'] as num).toInt()),
          saldoNum: (a['saldo'] as num).toInt(),
          masuk: uang(s.sum('masuk', a['id'])),
          keluar: uang(s.sum('keluar', a['id'])),
          hidden: widget.hide,
          onToggle: widget.onToggle,
        ),
      Semantics(
        button: true,
        label: 'Tambah kartu',
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => _form(),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white38, width: 1.5),
              color: Colors.white.withValues(alpha: 0.06),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_card_outlined, color: Colors.white, size: 36),
                  SizedBox(height: 10),
                  Text(
                    'Tambah kartu',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'E-wallet, rekening bank, tunai…',
                    style: TextStyle(color: Color(0xFFB8C4B5), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
    return Column(
      children: [
        LayoutBuilder(
          builder: (_, c) => SizedBox(
            height: c.maxWidth / 1.62,
            child: PageView(
              controller: ctrl,
              onPageChanged: (v) => setState(() => i = v),
              children: [
                for (final p in pages)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: p,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: 'Kartu ${i + 1} dari ${pages.length}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var k = 0; k < pages.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: k == i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: k == i ? C.lime : Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aktifkan kunci hanya setelah verifikasi berhasil, supaya tidak terkunci di HP tanpa biometrik/PIN.
class _SwitchKunci extends StatefulWidget {
  const _SwitchKunci();
  @override
  State<_SwitchKunci> createState() => _SwitchKunciState();
}

class _SwitchKunciState extends State<_SwitchKunci> {
  bool? on;

  @override
  void initState() {
    super.initState();
    kunciAktif().then((v) => mounted ? setState(() => on = v) : null);
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Icon(Icons.fingerprint, color: C.text),
    title: Text('Kunci aplikasi', style: TextStyle(color: C.text)),
    subtitle: Text(
      'Sidik jari, Face ID, atau PIN HP',
      style: TextStyle(color: C.muted),
    ),
    value: on ?? false,
    onChanged: on == null
        ? null
        : (v) async {
            if (!await verifikasi()) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Verifikasi gagal atau HP belum punya kunci layar',
                    ),
                  ),
                );
              }
              return;
            }
            await setKunci(v);
            if (mounted) setState(() => on = v);
          },
  );
}

/// Chip filter dengan menu pilihan; "Semua" mengosongkan filter.
class _Saring<T extends Object> extends StatelessWidget {
  final String label;
  final bool aktif;
  final Map<T, String> pilihan;
  final ValueChanged<T?> onPilih;
  const _Saring({
    required this.label,
    required this.aktif,
    required this.pilihan,
    required this.onPilih,
  });
  @override
  Widget build(BuildContext context) => PopupMenuButton<Object>(
    tooltip: 'Saring $label',
    onSelected: (v) => onPilih(v == '' ? null : v as T),
    itemBuilder: (_) => [
      const PopupMenuItem(value: '', child: Text('Semua')),
      for (final e in pilihan.entries)
        PopupMenuItem(value: e.key, child: Text(e.value)),
    ],
    child: Chip(
      label: Text('$label ▾'),
      backgroundColor: aktif ? C.btn : C.card,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: aktif ? C.onBtn : C.text,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
