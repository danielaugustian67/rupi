import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pilihan tampilan user, disimpan di HP (bukan per akun).
final temaMode = ValueNotifier(ThemeMode.system);

Future<void> muatTema() async {
  try {
    final i = (await SharedPreferences.getInstance()).getInt('tema');
    if (i != null && i >= 0 && i < ThemeMode.values.length) {
      temaMode.value = ThemeMode.values[i];
    }
  } catch (_) {} // gagal baca: tetap ikut sistem
}

Future<void> setTema(ThemeMode m) async {
  temaMode.value = m;
  try {
    await (await SharedPreferences.getInstance()).setInt('tema', m.index);
  } catch (_) {}
}

class C {
  static const dark = Color(0xFF0C1610);
  static const lime = Color(0xFF9BE27F);
  static const green = Color(0xFF4CAF50);

  /// Diset dari kecerahan sistem di MaterialApp.builder; seluruh UI dibangun ulang saat berubah.
  static bool gelap = false;
  static Color get bg =>
      gelap ? const Color(0xFF0B110D) : const Color(0xFFF3F5F1);
  static Color get card => gelap ? const Color(0xFF16201A) : Colors.white;
  static Color get text =>
      gelap ? const Color(0xFFE8ECE6) : const Color(0xFF14181B);
  static Color get muted =>
      gelap ? const Color(0xFF9AA39C) : const Color(0xFF5B6166);
  static Color get income =>
      gelap ? const Color(0xFF7CCB6B) : const Color(0xFF2F7A2A);
  static Color get expense =>
      gelap ? const Color(0xFFF08A52) : const Color(0xFFB4501A);
  static Color get line =>
      gelap ? const Color(0xFF26302A) : const Color(0xFFE4E8E0);
  static Color get track =>
      gelap ? const Color(0xFF26302A) : const Color(0xFFEEF0EB);

  /// Tombol utama: hitam di mode terang, lime di mode gelap.
  static Color get btn => gelap ? lime : dark;
  static Color get onBtn => gelap ? dark : Colors.white;
}

ThemeData appTheme(bool gelap) {
  C.gelap = gelap;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.green,
      surface: C.bg,
      brightness: gelap ? Brightness.dark : Brightness.light,
    ),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: GoogleFonts.soraTextTheme(base.textTheme)
        .apply(bodyColor: C.text, displayColor: C.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.btn,
        foregroundColor: C.onBtn,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
      ),
    ),
  );
}

/// Latar hijau-hitam bercahaya dari desain "Green Glow".
class GlowBox extends StatelessWidget {
  final Widget child;
  final BorderRadius? radius;
  const GlowBox({super.key, required this.child, this.radius});

  @override
  Widget build(BuildContext context) {
    BoxDecoration d(Gradient g) =>
        BoxDecoration(gradient: g, borderRadius: radius);
    // Status bar putih di atas latar gelap.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: d(
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A3020), Color(0xFF0A120B), Color(0xFF050906)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Container(
          decoration: d(
            const RadialGradient(
              center: Alignment(0.56, -0.44),
              radius: 0.9,
              colors: [Color(0xD978C85F), Color(0x8C346930), Color(0x0009100A)],
              stops: [0, 0.32, 0.68],
            ),
          ),
          child: Container(
            decoration: d(
              const RadialGradient(
                center: Alignment(-0.84, 0.9),
                radius: 0.7,
                colors: [Color(0x80509641), Color(0x0009100A)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Gradasi kartu hijau muda (Insight AI, ketik bebas).
const limeCard = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFC4F2AE), Color(0xFF8EDC74), Color(0xFF6CC35A)],
  stops: [0, 0.55, 1],
);

/// Halaman form/daftar di layar lebar (web desktop): batasi lebar, tengahkan.
Widget lebarMaks(Widget child, {double maks = 760}) => ColoredBox(
  color: C.bg,
  child: Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maks),
      child: child,
    ),
  ),
);
