import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keuangan_ai/menu.dart' show keWebp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('foto dikonversi ke WebP dan mengecil', (t) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    for (var i = 0; i < 300; i++) {
      c.drawCircle(
        Offset((i * 37) % 3000.0, (i * 53) % 2000.0),
        60,
        Paint()..color = Color(0xFF000000 + i * 49157),
      );
    }
    final img = await rec.endRecording().toImage(3000, 2000);
    final png = (await img.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final w = await keWebp(png);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WEBP');
    expect(w.length, lessThan(png.length));
    debugPrint('PNG ${png.length} -> WebP ${w.length} bytes');
  });
}
