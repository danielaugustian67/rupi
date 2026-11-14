import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const dark = Color(0xFF0C1610);
  static const lime = Color(0xFF9BE27F);
  static const green = Color(0xFF4CAF50);
  static const bg = Color(0xFFF3F5F1);
  static const text = Color(0xFF14181B);
  static const muted = Color(0xFF5B6166);
  static const income = Color(0xFF2F7A2A);
  static const expense = Color(0xFFB4501A);
  static const line = Color(0xFFE4E8E0);
}

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.green, surface: C.bg),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: GoogleFonts.soraTextTheme(base.textTheme)
        .apply(bodyColor: C.text, displayColor: C.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.dark,
        foregroundColor: Colors.white,
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
