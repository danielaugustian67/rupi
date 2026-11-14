import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

const _kunci = 'tutorial_v1';

/// Langkah panduan: (ikon, judul, isi).
const langkahTutorial = [
  (
    Icons.account_balance_wallet_outlined,
    'Selamat datang di Rupi',
    'Kartu di Beranda menunjukkan saldo, pemasukan, dan pengeluaran bulan ini. '
        'Ketuk ikon mata untuk menyembunyikan angka.',
  ),
  (
    Icons.add_circle_outline,
    'Catat dengan tombol +',
    'Ketik bebas seperti "makan bakso 25rb" atau "gaji 5jt", lalu AI yang mengisi '
        'formnya. Bisa juga lewat suara, scan struk, atau isi manual.',
  ),
  (
    Icons.bar_chart_rounded,
    'Transaksi & Laporan',
    'Tab Transaksi berisi semua catatan; ketuk satu untuk mengubah atau menghapus. '
        'Laporan menampilkan grafik, batas anggaran per kategori, dan ekspor CSV.',
  ),
  (
    Icons.savings_outlined,
    'Tabungan & Pinjaman',
    'Buat target tabungan lalu setor sedikit demi sedikit. Di Pinjaman, isi email '
        'teman supaya kalian berdua bisa melihat sisa yang belum kembali.',
  ),
  (
    Icons.chat_bubble_outline,
    'Tanya Chat AI',
    'Tanya apa saja soal keuanganmu, misalnya "bulan ini paling boros di mana?". '
        'AI membaca catatanmu untuk menjawab.',
  ),
];

/// Tampilkan panduan sekali saja (per HP) setelah login pertama.
Future<void> tutorialPertamaKali(BuildContext context) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kunci) ?? false) return;
    if (!context.mounted) return;
    await bukaTutorial(context);
    await p.setBool(_kunci, true);
  } catch (_) {} // gagal baca prefs: lewati, jangan ganggu user
}

Future<void> bukaTutorial(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(fullscreenDialog: true, builder: (_) => const Tutorial()),
);

class Tutorial extends StatefulWidget {
  const Tutorial({super.key});
  @override
  State<Tutorial> createState() => _TutorialState();
}

class _TutorialState extends State<Tutorial> {
  final ctrl = PageController();
  int i = 0;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final akhir = i == langkahTutorial.length - 1;
    return Scaffold(
      body: GlowBox(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Lewati',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: ctrl,
                  onPageChanged: (v) => setState(() => i = v),
                  children: [
                    for (final (ikon, judul, isi) in langkahTutorial)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: const BoxDecoration(
                                gradient: limeCard,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(ikon, size: 56, color: C.dark),
                            ),
                            const SizedBox(height: 36),
                            Text(
                              judul,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              isi,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFB8C4B5),
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Semantics(
                label: 'Langkah ${i + 1} dari ${langkahTutorial.length}',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var k = 0; k < langkahTutorial.length; k++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: k == i ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: k == i ? C.lime : Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: C.lime,
                    foregroundColor: C.dark,
                  ),
                  onPressed: () => akhir
                      ? Navigator.pop(context)
                      : ctrl.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        ),
                  child: Text(akhir ? 'Mulai' : 'Lanjut'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
