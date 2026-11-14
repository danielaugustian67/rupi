/// 3250000 -> "Rp3.250.000"
String rp(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-Rp' : 'Rp');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Nominal dari kalimat bebas: "bakso 25rb" -> 25000, "gaji 7,5jt" -> 7500000.
/// Dipakai sebelum/tanpa AI supaya form langsung terisi.
int? parseNominal(String text) {
  final m = RegExp(
    r'(\d+(?:[.,]\d+)*)\s*(rb|ribu|k|jt|juta)?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  final unit = (m.group(2) ?? '').toLowerCase();
  var n = m.group(1)!;
  if (unit.isEmpty) return int.tryParse(n.replaceAll(RegExp(r'[.,]'), ''));
  // Dengan satuan, koma/titik adalah desimal: "7,5jt".
  final v = double.tryParse(n.replaceAll(',', '.'));
  if (v == null) return null;
  final mult = (unit == 'jt' || unit == 'juta') ? 1000000 : 1000;
  return (v * mult).round();
}
