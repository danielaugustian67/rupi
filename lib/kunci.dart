import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

final _auth = LocalAuthentication();

/// Kunci app (sidik jari / Face ID / PIN HP). Disimpan per HP.
Future<bool> kunciAktif() async {
  if (kIsWeb) return false;
  try {
    return (await SharedPreferences.getInstance()).getBool('kunci') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> setKunci(bool v) async =>
    (await SharedPreferences.getInstance()).setBool('kunci', v);

/// True kalau pemilik HP berhasil verifikasi (biometrik atau PIN/pola HP).
Future<bool> verifikasi() async {
  try {
    return await _auth.authenticate(localizedReason: 'Buka Rupi');
  } catch (_) {
    return false; // mis. HP tanpa kunci layar
  }
}

/// Layar terkunci di atas app; [onLogout] jalan keluar kalau verifikasi tidak bisa.
class LayarKunci extends StatelessWidget {
  final VoidCallback onBuka, onLogout;
  const LayarKunci({super.key, required this.onBuka, required this.onLogout});
  @override
  Widget build(BuildContext context) => Material(
    color: C.dark,
    child: SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, color: C.lime, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Rupi terkunci',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, 52),
              backgroundColor: C.lime,
              foregroundColor: C.dark,
            ),
            onPressed: onBuka,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Buka'),
          ),
          TextButton(
            onPressed: onLogout,
            child: const Text(
              'Keluar akun (masuk lagi pakai password)',
              style: TextStyle(color: Color(0xFFB8C4B5)),
            ),
          ),
        ],
      ),
    ),
  );
}
