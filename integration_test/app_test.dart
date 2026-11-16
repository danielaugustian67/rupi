// E2E: jalankan app asli di simulator, lalu ketuk & ketik seperti user.
// flutter test integration_test -d <device> --dart-define-from-file=.env.json
// Kalau belum login, isi TEST_EMAIL & TEST_PASSWORD di .env.json.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keuangan_ai/main.dart' as app;
import 'package:keuangan_ai/anim.dart';
import 'package:keuangan_ai/theme.dart';

Future<void> tunggu(
  WidgetTester t,
  Finder f, {
  Duration batas = const Duration(seconds: 20),
}) async {
  final akhir = DateTime.now().add(batas);
  while (DateTime.now().isBefore(akhir)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Tidak muncul dalam ${batas.inSeconds} detik: $f');
}

Future<void> ketuk(WidgetTester t, Finder f) async {
  await tunggu(t, f);
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 600));
}

/// pumpAndSettle dengan batas 5 dtk (animasi tak berujung tidak membuat tes macet).
Future<void> settle(WidgetTester t) async {
  try {
    await t.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  } on FlutterError {
    // masih ada animasi berulang (mis. indikator loading); lanjut saja
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('alur utama: login, tambah, cek tab, mode gelap, hapus', (
    t,
  ) async {
    await app.main();
    final beranda = find.byIcon(Icons.home_outlined);
    final login = find.widgetWithText(TextField, 'Email');
    final akhir = DateTime.now().add(const Duration(seconds: 20));
    while (beranda.evaluate().isEmpty && login.evaluate().isEmpty) {
      if (DateTime.now().isAfter(akhir)) fail('App tidak tampil');
      await t.pump(const Duration(milliseconds: 250));
    }

    // 1. Login (kalau sesi belum ada)
    if (login.evaluate().isNotEmpty) {
      const email = String.fromEnvironment('TEST_EMAIL');
      const pass = String.fromEnvironment('TEST_PASSWORD');
      if (email.isEmpty || pass.isEmpty) {
        fail('Belum login: isi TEST_EMAIL & TEST_PASSWORD di .env.json');
      }
      await t.enterText(login, email);
      await t.enterText(find.widgetWithText(TextField, 'Password'), pass);
      await ketuk(t, find.text('Masuk').last);
    }

    // 2. Panduan pertama kali (akun/HP baru): geser sampai habis
    final lanjut = find.text('Lanjut');
    final akhirP = DateTime.now().add(const Duration(seconds: 8));
    // Panduan muncul sesaat setelah Beranda, jadi tunggu panduannya sendiri.
    while (lanjut.evaluate().isEmpty && DateTime.now().isBefore(akhirP)) {
      await t.pump(const Duration(milliseconds: 250));
    }
    if (lanjut.evaluate().isNotEmpty) {
      for (var k = 0; k < 4; k++) {
        await ketuk(t, lanjut);
      }
      await ketuk(t, find.text('Mulai'));
    }

    // Beranda
    await tunggu(t, find.text('RUPI'));
    await tunggu(t, find.text('Transaksi terakhir'));

    // 3. Tambah transaksi manual
    final nama = 'E2E ${DateTime.now().millisecondsSinceEpoch % 100000}';
    await ketuk(t, find.byIcon(Icons.add));
    await ketuk(t, find.text('Manual'));
    await tunggu(t, find.text('Jumlah (Rp)'));
    await t.enterText(find.widgetWithText(TextField, 'Jumlah (Rp)'), '12345');
    await t.enterText(
      find.widgetWithText(TextField, 'Toko / keterangan'),
      nama,
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await ketuk(t, find.text('Ulangi tiap bulan'));
    await ketuk(t, find.widgetWithText(FilledButton, 'Simpan'));

    // 4. Muncul di tab Transaksi, juga di daftar rutin (lalu dihentikan)
    await ketuk(t, find.byIcon(Icons.format_list_bulleted));
    await tunggu(t, find.text(nama));
    await ketuk(t, find.byTooltip('Transaksi rutin'));
    await tunggu(t, find.text(nama));
    await ketuk(t, find.byTooltip('Hentikan'));
    await ketuk(t, find.widgetWithText(TextButton, 'Hentikan'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text(nama), findsNothing);
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));

    // 5. Tab Laporan & Chat terbuka tanpa error
    await ketuk(t, find.byIcon(Icons.bar_chart_rounded));
    await tunggu(t, find.textContaining('Anggaran'));
    await ketuk(t, find.byIcon(Icons.chat_bubble_outline));
    await t.pump(const Duration(seconds: 2));

    // 6. Halaman Menu (dari Beranda & tombol +) dengan kode teman
    await ketuk(t, beranda);
    await ketuk(t, find.text('Menu').first);
    await tunggu(t, find.text('Kode temanmu'));
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));
    await ketuk(t, find.byIcon(Icons.add));
    await ketuk(t, find.text('Menu').last);
    await tunggu(t, find.text('Menu baru'));
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));

    // 7. Mode gelap lalu kembali terang (gulir ke atas dulu: tombol ada di header)
    await t.drag(find.text('Transaksi terakhir'), const Offset(0, 700));
    await t.pump(const Duration(seconds: 2));
    await ketuk(t, find.byTooltip('Tampilan'));
    await ketuk(t, find.text('Gelap'));
    await t.pump(const Duration(seconds: 1));
    expect(C.gelap, isTrue);
    expect(find.text('RUPI'), findsOneWidget);
    await ketuk(t, find.byTooltip('Tampilan'));
    await ketuk(t, find.text('Terang'));
    await t.pump(const Duration(seconds: 1));
    expect(C.gelap, isFalse);

    // 8. Hapus transaksi uji lewat UI (bersih-bersih data)
    await ketuk(t, find.byIcon(Icons.format_list_bulleted));
    await ketuk(t, find.text(nama));
    await ketuk(t, find.byTooltip('Hapus'));
    await ketuk(t, find.widgetWithText(TextButton, 'Hapus'));
    await t.pump(const Duration(seconds: 2));
    await tunggu(t, find.byIcon(Icons.format_list_bulleted));
    for (var i = 0; i < 20 && find.text(nama).evaluate().isNotEmpty; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(find.text(nama), findsNothing);

    // 9. Ketik bebas: AI (atau parser cadangan) mengisi form
    await ketuk(t, find.byIcon(Icons.add));
    await t.enterText(
      find.widgetWithText(TextField, 'Ketik jumlah & keterangan'),
      'bonus akhir tahun 750rb',
    );
    await ketuk(t, find.byTooltip('Kirim'));
    await tunggu(
      t,
      find.text('Jumlah (Rp)'),
      batas: const Duration(seconds: 30),
    );
    final jumlah = t.widget<TextField>(
      find.widgetWithText(TextField, 'Jumlah (Rp)'),
    );
    expect(jumlah.controller!.text.replaceAll(RegExp(r'\D'), ''), '750000');
    final seg = t.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(seg.selected, {'masuk'}, reason: 'bonus harus jadi pemasukan');
    final toko = t
        .widget<TextField>(find.widgetWithText(TextField, 'Toko / keterangan'))
        .controller!;
    final namaAi = 'AI ${DateTime.now().millisecondsSinceEpoch % 100000}';
    toko.text = namaAi;
    await ketuk(t, find.widgetWithText(FilledButton, 'Simpan'));
    await ketuk(t, find.byIcon(Icons.format_list_bulleted));
    await ketuk(t, find.text(namaAi));
    await ketuk(t, find.byTooltip('Hapus'));
    await ketuk(t, find.widgetWithText(TextButton, 'Hapus'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text(namaAi), findsNothing);

    // 10. Menu custom: buat, AI memasukkan item, ceklis lunas, hapus
    final namaMenu = 'Bill E2E ${DateTime.now().millisecondsSinceEpoch % 1000}';
    await ketuk(t, beranda);
    await t.drag(find.text('Transaksi terakhir'), const Offset(0, 700));
    await t.pump(const Duration(seconds: 1));
    await ketuk(t, find.text('Menu').first);
    await ketuk(t, find.text('Menu baru'));
    await t.enterText(find.widgetWithText(TextField, 'Nama menu'), namaMenu);
    await ketuk(t, find.text('Simpan'));
    await tunggu(t, find.text('Belum lunas')); // halaman menu terbuka
    // Sheet Teman: kolom kode & tombol Undang tampil untuk pemilik
    await ketuk(t, find.byTooltip('Teman'));
    await tunggu(t, find.widgetWithText(TextField, 'Kode teman'));
    expect(find.text('Undang'), findsOneWidget);
    Navigator.of(t.element(find.text('Teman di menu ini'))).pop();
    await t.pump(const Duration(seconds: 1));
    // Tambah manual
    await ketuk(t, find.text('Tambah'));
    await t.enterText(find.widgetWithText(TextField, 'Nominal (Rp)'), '75000');
    await t.enterText(find.widgetWithText(TextField, 'Judul'), 'Pulsa');
    await ketuk(t, find.widgetWithText(FilledButton, 'Simpan'));
    await tunggu(t, find.text('Pulsa'));
    // Ceklis lunas tanpa mencatat transaksi
    await ketuk(t, find.byTooltip('Tandai lunas'));
    await ketuk(t, find.text('Lunas saja'));
    await tunggu(t, find.byIcon(Icons.check_circle_rounded));
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));

    // AI: kalimat yang menyebut nama menu masuk ke menu itu
    await ketuk(t, find.byIcon(Icons.add));
    await t.enterText(
      find.widgetWithText(TextField, 'Ketik jumlah & keterangan'),
      '${namaMenu.toLowerCase()} sepatu 300rb',
    );
    await ketuk(t, find.byTooltip('Kirim'));
    await tunggu(
      t,
      find.text('Nominal (Rp)'),
      batas: const Duration(seconds: 30),
    );
    expect(find.text(namaMenu), findsOneWidget, reason: 'AI salah pilih menu');
    final nominalAi = t.widget<TextField>(
      find.widgetWithText(TextField, 'Nominal (Rp)'),
    );
    expect(nominalAi.controller!.text.replaceAll(RegExp(r'\D'), ''), '300000');
    await ketuk(t, find.widgetWithText(FilledButton, 'Simpan'));

    // Buka menunya, cek total belum lunas, lalu hapus menu
    await ketuk(t, beranda);
    await ketuk(t, find.text('Menu').first);
    await ketuk(t, find.text(namaMenu));
    await tunggu(t, find.text('Rp300.000'));
    await ketuk(t, find.byTooltip('Lainnya'));
    await ketuk(t, find.text('Hapus menu'));
    await ketuk(t, find.widgetWithText(TextButton, 'Hapus'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text(namaMenu), findsNothing);
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));

    // 11. Kartu saldo: buat 2 kartu, transfer antar kartu, hapus semuanya
    Future<void> geserKe(Finder f) async {
      await ketuk(t, beranda);
      await t.scrollUntilVisible(
        find.byType(PageView),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      // Cari ke kanan dulu, lalu balik ke kiri kalau sudah mentok.
      for (final dx in [-500.0, 500.0]) {
        for (var n = 0; n < 12 && f.hitTestable().evaluate().isEmpty; n++) {
          await t.drag(find.byType(PageView), Offset(dx, 0));
          await settle(t);
        }
      }
    }

    final id = DateTime.now().millisecondsSinceEpoch % 1000;
    final kartu = 'Kartu E2E $id', kartu2 = 'Dompet E2E $id';
    for (final (k, saldo) in [(kartu, '54321'), (kartu2, '0')]) {
      await geserKe(find.text('Tambah kartu'));
      await ketuk(t, find.text('Tambah kartu'));
      await t.enterText(find.widgetWithText(TextField, 'Nama kartu'), k);
      await t.enterText(find.widgetWithText(TextField, 'Saldo awal'), saldo);
      await ketuk(t, find.widgetWithText(TextButton, 'Simpan'));
      await t.pump(const Duration(seconds: 2));
    }
    await geserKe(find.text('$kartu'));
    await tunggu(t, find.text('Rp54.321'));

    await ketuk(t, find.byIcon(Icons.add));
    await ketuk(t, find.text('Transfer'));
    await t.enterText(find.widgetWithText(TextField, 'Jumlah (Rp)'), '4321');
    await ketuk(t, find.widgetWithText(TextButton, 'Transfer'));
    await t.pump(const Duration(seconds: 2));
    await geserKe(find.text('$kartu'));
    await tunggu(t, find.text('Rp50.000'));
    // Transfer tampil di daftar, bisa dihapus (kedua sisinya)
    await ketuk(t, find.byIcon(Icons.format_list_bulleted));
    await ketuk(t, find.text('Transfer ke $kartu2'));
    await ketuk(t, find.widgetWithText(TextButton, 'Hapus transfer'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Transfer dari $kartu'), findsNothing);

    for (final k in [kartu, kartu2]) {
      await geserKe(find.text('$k'));
      await settle(t);
      await t.tap(find.byTooltip('Ubah kartu').hitTestable().first);
      await t.pump(const Duration(milliseconds: 700));
      await tunggu(t, find.text('Ubah kartu'));
      await ketuk(t, find.widgetWithText(TextButton, 'Hapus'));
      await ketuk(t, find.widgetWithText(TextButton, 'Hapus').last);
      await t.pump(const Duration(seconds: 2));
      expect(find.text('$k'), findsNothing);
    }

    // 12. Chat AI menjawab
    await ketuk(t, find.byIcon(Icons.chat_bubble_outline));
    await t.enterText(
      find.widgetWithText(TextField, 'Tanya soal keuanganmu…'),
      'Halo, beri satu tips hemat singkat',
    );
    await ketuk(t, find.byTooltip('Kirim'));
    await tunggu(t, find.byType(TypingDots));
    final selesai = DateTime.now().add(const Duration(seconds: 40));
    while (find.byType(TypingDots).evaluate().isNotEmpty &&
        DateTime.now().isBefore(selesai)) {
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(TypingDots), findsNothing, reason: 'AI tidak menjawab');
    expect(
      find.textContaining(
        RegExp('tidak tersedia|terlalu lama|sudah habis|belum disetel'),
      ),
      findsNothing,
      reason: 'AI membalas dengan pesan error',
    );
  });
}
