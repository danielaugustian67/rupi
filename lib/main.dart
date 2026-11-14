import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages.dart';
import 'theme.dart';

SupabaseClient get db => Supabase.instance.client;

// appTheme() ikut mengubah C.gelap, jadi pelacak perubahan mode terpisah.
bool? _gelapTerakhir;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_KEY'),
  );
  await muatTema();
  runApp(
    ValueListenableBuilder(
      valueListenable: temaMode,
      builder: (_, mode, _) => MaterialApp(
        title: 'Keuangan AI',
        debugShowCheckedModeBanner: false,
        theme: appTheme(false),
        darkTheme: appTheme(true),
        themeMode: mode,
        // Set C.gelap sebelum subtree dibangun.
        builder: (ctx, child) {
          C.gelap =
              mode == ThemeMode.dark ||
              (mode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(ctx) == Brightness.dark);
          // Warna C.* dibaca langsung (bukan via Theme), jadi bangun ulang
          // seluruh pohon widget saat mode berganti; halaman & state tetap.
          if (_gelapTerakhir != null && _gelapTerakhir != C.gelap) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              void semua(Element e) {
                e.markNeedsBuild();
                e.visitChildren(semua);
              }

              WidgetsBinding.instance.rootElement?.visitChildren(semua);
            });
          }
          _gelapTerakhir = C.gelap;
          return child!;
        },
        home: db.auth.currentSession == null
            ? const LoginPage()
            : const Shell(),
      ),
    ),
  );
}

// Login wajib: data keuangan dilindungi RLS per user, key publik saja tidak bisa baca.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool daftar = false; // false = mode masuk, true = mode daftar

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _login() async {
    final mail = email.text.trim();
    if (!mail.contains('@')) return _toast('Email tidak valid');
    if (password.text.length < 6) return _toast('Password minimal 6 karakter');
    setState(() => busy = true);
    try {
      if (daftar) {
        final res = await db.auth.signUp(email: mail, password: password.text);
        if (res.session == null) {
          // Konfirmasi email aktif: user harus klik link di email dulu.
          if (mounted) {
            setState(() => daftar = false);
            _toast(
              'Akun dibuat. Cek email $mail untuk konfirmasi, lalu masuk.',
            );
          }
          return;
        }
      } else {
        await db.auth.signInWithPassword(email: mail, password: password.text);
      }
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Shell()),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration _glass(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFFB8C4B5)),
    prefixIcon: Icon(icon, color: const Color(0xFFB8C4B5)),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.08),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: const BorderSide(color: C.lime, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 18),
  );

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GlowBox(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    const _HeroCard(),
                    const SizedBox(height: 32),
                    Text(
                      daftar ? 'Buat akun\nbaru' : 'Atur uangmu\nlebih cerdas',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Catat transaksi, scan struk, dan tanya AI\nsoal keuanganmu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFB8C4B5),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: email,
                      style: white,
                      cursorColor: C.lime,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: _glass('Email', Icons.mail_outline),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      style: white,
                      cursorColor: C.lime,
                      obscureText: true,
                      autofillHints: [
                        daftar
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onSubmitted: (_) => _login(),
                      decoration: _glass('Password', Icons.lock_outline),
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      button: true,
                      label: daftar ? 'Daftar' : 'Masuk',
                      child: Material(
                        color: C.lime,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: busy ? null : _login,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Row(
                              children: [
                                const SizedBox(width: 52),
                                Expanded(
                                  child: Text(
                                    busy
                                        ? 'Memproses…'
                                        : (daftar ? 'Daftar' : 'Masuk'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: C.dark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: const BoxDecoration(
                                    color: C.dark,
                                    shape: BoxShape.circle,
                                  ),
                                  child: busy
                                      ? const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: C.lime,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.arrow_forward,
                                          color: Colors.white,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => daftar = !daftar),
                      child: Text.rich(
                        TextSpan(
                          text: daftar
                              ? 'Sudah punya akun? '
                              : 'Belum punya akun? ',
                          style: const TextStyle(color: Color(0xFFB8C4B5)),
                          children: [
                            TextSpan(
                              text: daftar ? 'Masuk' : 'Daftar',
                              style: const TextStyle(
                                color: C.lime,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu saldo lime miring, visual utama layar login.
class _HeroCard extends StatelessWidget {
  const _HeroCard();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -0.22,
            child: Container(
              width: 270,
              height: 165,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
          ),
          Transform.rotate(
            angle: -0.12,
            child: Container(
              width: 280,
              height: 170,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: limeCard,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Saldo bulan ini',
                          style: TextStyle(
                            color: Color(0xFF24361F),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: C.dark),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '▲ 12%',
                          style: TextStyle(
                            color: C.dark,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'Rp3.250.000',
                    style: TextStyle(
                      color: C.dark,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Keuangan AI',
                    style: TextStyle(
                      color: Color(0xFF24361F),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
