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

    // 2. Beranda
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
    await ketuk(t, find.widgetWithText(FilledButton, 'Simpan'));

    // 4. Muncul di tab Transaksi
    await ketuk(t, find.byIcon(Icons.format_list_bulleted));
    await tunggu(t, find.text(nama));

    // 5. Tab Laporan & Chat terbuka tanpa error
    await ketuk(t, find.byIcon(Icons.bar_chart_rounded));
    await tunggu(t, find.textContaining('Anggaran'));
    await ketuk(t, find.byIcon(Icons.chat_bubble_outline));
    await t.pump(const Duration(seconds: 2));

    // 6. Halaman Tabungan & Pinjaman
    await ketuk(t, beranda);
    await ketuk(t, find.text('Tabungan'));
    await tunggu(t, find.text('Tabungan baru'));
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));
    await ketuk(t, find.byIcon(Icons.add));
    await ketuk(t, find.text('Pinjaman'));
    await tunggu(t, find.text('Dipinjamkan'));
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
      find.widgetWithText(TextField, 'contoh: makan bakso 25rb'),
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

    // 10. Tabungan: buat, setor, hapus
    await ketuk(t, beranda);
    await t.drag(find.text('Transaksi terakhir'), const Offset(0, 700));
    await t.pump(const Duration(seconds: 1));
    await ketuk(t, find.text('Tabungan'));
    await ketuk(t, find.text('Tabungan baru'));
    final namaTab = 'Tab E2E ${DateTime.now().millisecondsSinceEpoch % 1000}';
    await t.enterText(find.widgetWithText(TextField, 'Nama'), namaTab);
    await ketuk(t, find.text('Simpan'));
    await ketuk(t, find.text(namaTab));
    await ketuk(t, find.text('Setor'));
    await t.enterText(find.widgetWithText(TextField, 'Nominal'), '100000');
    if (t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value ??
        false) {
      await ketuk(t, find.byType(CheckboxListTile)); // jangan buat transaksi
    }
    await ketuk(t, find.text('Simpan'));
    await tunggu(t, find.text('Rp100.000'));
    if (find.text('Hapus').evaluate().isEmpty)
      await ketuk(t, find.text(namaTab));
    await ketuk(t, find.text('Hapus'));
    await ketuk(t, find.widgetWithText(TextButton, 'Hapus'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text(namaTab), findsNothing);
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));

    // 11. Pinjaman: buat, catat pengembalian, hapus
    await ketuk(t, find.byIcon(Icons.add));
    await ketuk(t, find.text('Pinjaman'));
    await ketuk(t, find.byType(FloatingActionButton));
    final namaP = 'Teman E2E ${DateTime.now().millisecondsSinceEpoch % 1000}';
    await t.enterText(find.widgetWithText(TextField, 'Nama orang'), namaP);
    await t.enterText(find.widgetWithText(TextField, 'Nominal'), '200000');
    await ketuk(t, find.widgetWithText(FilledButton, 'Simpan'));
    await ketuk(t, find.text(namaP));
    await ketuk(t, find.text('Catat pengembalian'));
    await t.enterText(find.widgetWithText(TextField, 'Nominal'), '50000');
    await ketuk(t, find.text('Simpan'));
    await tunggu(t, find.text('Rp150.000'));
    if (find.text('Hapus').evaluate().isEmpty) await ketuk(t, find.text(namaP));
    await ketuk(t, find.text('Hapus'));
    await ketuk(t, find.widgetWithText(TextButton, 'Hapus'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text(namaP), findsNothing);
    await t.pageBack();
    await t.pump(const Duration(seconds: 1));

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
