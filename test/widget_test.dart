import 'package:flutter_test/flutter_test.dart';
import 'package:keuangan_ai/chat.dart' show pesanError;
import 'package:keuangan_ai/format.dart';
import 'package:keuangan_ai/laporan.dart';
import 'package:keuangan_ai/notif.dart' show waktuTempo;
import 'package:keuangan_ai/receipt.dart';
import 'package:keuangan_ai/menu.dart' show ringkasItem;

void main() {
  test('parseRupiah', () {
    expect(parseRupiah('TOTAL 45.500'), 45500);
    expect(parseRupiah('Total Rp1.250.000,00'), 1250000);
    expect(parseRupiah('TOTAL 12000'), 12000);
    expect(parseRupiah('TOTAL'), null);
  });

  test('findTotal skips subtotal', () {
    expect(
      findTotal('SUBTOTAL 40.000\nPPN 4.000\nTOTAL 44.000\nTUNAI 50.000'),
      44000,
    );
  });

  test('rp', () {
    expect(rp(3250000), 'Rp3.250.000');
    expect(rp(500), 'Rp500');
    expect(rp(-45500), '-Rp45.500');
  });

  test('parseNominal', () {
    expect(parseNominal('makan bakso 25rb'), 25000);
    expect(parseNominal('gaji 7,5jt'), 7500000);
    expect(parseNominal('kopi 18k'), 18000);
    expect(parseNominal('bayar listrik 350.000'), 350000);
    expect(parseNominal('makan siang'), null);
  });

  test('laporan agregasi', () {
    final rows = [
      {
        'tipe': 'keluar',
        'kategori': 'makan',
        'jumlah': 20000,
        'tanggal': '2026-11-03',
      },
      {
        'tipe': 'keluar',
        'kategori': 'makan',
        'jumlah': 5000,
        'tanggal': '2026-11-03',
      },
      {
        'tipe': 'keluar',
        'kategori': 'transport',
        'jumlah': 30000,
        'tanggal': '2026-11-30',
      },
      {
        'tipe': 'masuk',
        'kategori': 'gaji',
        'jumlah': 999,
        'tanggal': '2026-11-01',
      },
    ];
    final k = keluarPerKategori(rows);
    expect(k.map((e) => '${e.key}:${e.value}'), [
      'transport:30000',
      'makan:25000',
    ]);
    final h = keluarPerHari(rows, DateTime(2026, 11));
    expect(h.length, 30);
    expect(h[2], 25000);
    expect(h[29], 30000);
    expect(h[0], 0);
  });

  test('ringkasItem menu: total, lunas, sisa', () {
    final s = ringkasItem([
      {'nominal': 100000, 'lunas': true},
      {'nominal': 50000, 'lunas': false},
      {'nominal': 25000},
    ]);
    expect(s.total, 175000);
    expect(s.lunas, 100000);
    expect(s.sisa, 75000);
  });

  test('pesanError', () {
    expect(pesanError({'error': 'limit'}), contains('habis'));
    expect(pesanError(null), contains('tidak tersedia'));
  });
  test('statusAnggaran', () {
    expect(statusAnggaran(500000, 1000000), 'aman');
    expect(statusAnggaran(850000, 1000000), 'hampir');
    expect(statusAnggaran(1000000, 1000000), 'lewat');
  });

  test('keCsv urut lama ke baru & escape koma', () {
    final csv = keCsv([
      {
        'tanggal': '2026-11-02',
        'tipe': 'keluar',
        'kategori': 'makan',
        'toko': 'Bakso, Pak "Kumis"',
        'jumlah': 25000,
      },
      {
        'tanggal': '2026-11-01',
        'tipe': 'masuk',
        'kategori': 'gaji',
        'toko': 'Gaji',
        'jumlah': 7000000,
      },
    ]);
    expect(csv.split('\n'), [
      'tanggal,tipe,kategori,keterangan,jumlah',
      '2026-11-01,masuk,gaji,Gaji,7000000',
      '2026-11-02,keluar,makan,"Bakso, Pak ""Kumis""",25000',
      '',
    ]);
  });

  test('waktuTempo jam 9 pagi, lewat = null', () {
    final now = DateTime(2026, 11, 14, 10);
    expect(waktuTempo('2026-11-20', now), DateTime(2026, 11, 20, 9));
    expect(waktuTempo('2026-11-14', now), null);
  });
}
