import 'package:supabase_flutter/supabase_flutter.dart';

/// "45.500" / "45,500" / "Rp45.500,00" -> 45500
int? parseRupiah(String s) {
  final m = RegExp(r'(\d{1,3}(?:[.,]\d{3})+|\d+)(?:[.,]\d{2})?\s*$')
      .firstMatch(s.trim());
  if (m == null) return null;
  return int.tryParse(m.group(1)!.replaceAll(RegExp(r'[.,]'), ''));
}

/// Ambil total dari teks OCR secara instan, tanpa AI.
int? findTotal(String text) {
  for (final line in text.split('\n')) {
    final l = line.toUpperCase();
    if (l.contains('TOTAL') && !l.contains('SUB')) {
      final v = parseRupiah(line);
      if (v != null) return v;
    }
  }
  return null;
}

/// Teks OCR/kalimat bebas -> {toko, total, tipe, kategori} lewat Edge Function `parse-trx`
/// (key OpenRouter + batas harian ada di server). Null kalau gagal, form tetap bisa diisi manual.
Future<Map<String, dynamic>?> parseWithAi(String text) async {
  try {
    final res = await Supabase.instance.client.functions
        .invoke('parse-trx', body: {'text': text})
        .timeout(const Duration(seconds: 12));
    final d = res.data;
    return d is Map<String, dynamic> && d['error'] == null ? d : null;
  } catch (_) {
    return null;
  }
}
