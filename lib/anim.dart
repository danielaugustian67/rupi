import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

/// Tiga titik yang naik-turun bergantian: "AI sedang berpikir".
class TypingDots extends StatefulWidget {
  final Color color;
  final double size;
  const TypingDots({super.key, this.color = C.muted, this.size = 8});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sedang berpikir',
      child: AnimatedBuilder(
        animation: c,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (_) {
                  // Tiap titik tertunda 0.2 siklus dari titik sebelumnya.
                  final t = (c.value - i * 0.2) % 1.0;
                  final up = t < 0.5 ? math.sin(t * 2 * math.pi) : 0.0;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: widget.size / 4),
                    child: Transform.translate(
                      offset: Offset(0, -up * widget.size * 0.8),
                      child: Opacity(
                        opacity: 0.35 + 0.65 * up.clamp(0, 1),
                        child: Container(
                          width: widget.size,
                          height: widget.size,
                          decoration: BoxDecoration(
                            color: widget.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Angka rupiah yang "menghitung" ke nilai baru.
class AnimatedRp extends StatelessWidget {
  final num value;
  final TextStyle? style;
  const AnimatedRp(this.value, {super.key, this.style});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Text(rp(v.round()), style: style),
  );
}

/// Bar progres yang terisi halus.
class AnimatedBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const AnimatedBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => LinearProgressIndicator(
        value: v,
        minHeight: height,
        color: color,
        backgroundColor: const Color(0xFFEEF0EB),
      ),
    ),
  );
}

/// Muncul pelan dari bawah; [index] memberi jeda bertingkat untuk daftar.
class FadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeIn({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 350 + 60 * math.min(index, 8)),
    curve: Curves.easeOutCubic,
    builder: (_, v, c) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c),
    ),
    child: child,
  );
}
