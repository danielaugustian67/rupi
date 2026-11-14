import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'anim.dart';
import 'main.dart' show db;
import 'theme.dart';

const _saran = [
  'Pengeluaran terbesarku bulan ini apa?',
  'Bandingkan bulan ini dengan bulan lalu',
  'Siapa saja yang masih meminjam uangku?',
  'Kasih tips hemat dari pola belanjaku',
];

/// Pesan error yang ramah untuk kode error dari fungsi `chat`.
String pesanError(Object? data) {
  final e = data is Map ? data['error'] : null;
  return switch (e) {
    'limit' => 'Jatah AI hari ini sudah habis. Coba lagi besok ya.',
    'ai_not_configured' => 'AI belum disetel di server.',
    'timeout' => 'AI terlalu lama menjawab. Coba tanya lagi.',
    _ => 'AI sedang tidak tersedia. Coba lagi sebentar lagi.',
  };
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final msgs = <Map<String, String>>[];
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  /// Riwayat tersimpan di tabel chat_pesan (50 terakhir).
  Future<void> _muat() async {
    try {
      final r = await db
          .from('chat_pesan')
          .select('role,content')
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        msgs.insertAll(0, [
          for (final m in r.reversed)
            {'role': '${m['role']}', 'content': '${m['content']}'},
        ]);
      });
      _turun();
    } catch (_) {
      // Riwayat opsional; chat tetap bisa dipakai.
    }
  }

  Future<void> _simpan(String role, String content) async {
    try {
      await db.from('chat_pesan').insert({'role': role, 'content': content});
    } catch (_) {}
  }

  Future<void> _hapusRiwayat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus riwayat chat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(msgs.clear);
    try {
      await db.from('chat_pesan').delete().gt('id', 0);
    } catch (_) {}
  }

  Future<void> _kirim([String? teks]) async {
    final t = (teks ?? ctrl.text).trim();
    if (t.isEmpty || busy) return;
    ctrl.clear();
    setState(() {
      msgs.add({'role': 'user', 'content': t});
      busy = true;
    });
    _turun();
    String reply;
    var err = true;
    try {
      final res = await db.functions
          .invoke(
            'chat',
            body: {
              // Pesan error lokal tidak dikirim ke AI.
              'messages': msgs.where((m) => m['err'] == null).toList(),
            },
          )
          .timeout(const Duration(seconds: 25));
      final d = res.data;
      if (d is Map && d['reply'] is String) {
        reply = d['reply'];
        err = false;
      } else {
        reply = pesanError(d);
      }
    } on FunctionException catch (e) {
      reply = pesanError(e.details);
    } catch (_) {
      reply = pesanError(null);
    }
    if (!mounted) return;
    if (!err) {
      _simpan('user', t);
      _simpan('assistant', reply);
    }
    setState(() {
      msgs.add({'role': 'assistant', 'content': reply, if (err) 'err': '1'});
      busy = false;
    });
    _turun();
  }

  void _turun() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Chat AI',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                if (msgs.isNotEmpty)
                  IconButton(
                    tooltip: 'Hapus riwayat chat',
                    onPressed: busy ? null : _hapusRiwayat,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
          ),
          Expanded(
            child: msgs.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: limeCard,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Text(
                          'Tanya apa saja soal keuanganmu. AI membaca '
                          'transaksi 3 bulan terakhir dan catatan pinjamanmu.',
                          style: TextStyle(
                            color: C.dark,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final s in _saran)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: C.card,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(s),
                              trailing: const Icon(Icons.north_east, size: 18),
                              onTap: () => _kirim(s),
                            ),
                          ),
                        ),
                    ],
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: msgs.length + (busy ? 1 : 0),
                    itemBuilder: (_, i) => i == msgs.length
                        ? const FadeIn(
                            child: _Bubble(teks: '', user: false, typing: true),
                          )
                        : FadeIn(
                            key: ValueKey(i),
                            child: _Bubble(
                              teks: msgs[i]['content']!,
                              user: msgs[i]['role'] == 'user',
                              muted: msgs[i]['err'] != null,
                            ),
                          ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _kirim(),
                    decoration: const InputDecoration(
                      hintText: 'Tanya soal keuanganmu…',
                      filled: false,
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Kirim',
                  style: IconButton.styleFrom(backgroundColor: C.dark),
                  onPressed: busy ? null : _kirim,
                  icon: const Icon(Icons.arrow_upward, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String teks;
  final bool user, muted, typing;
  const _Bubble({
    required this.teks,
    required this.user,
    this.muted = false,
    this.typing = false,
  });
  @override
  Widget build(BuildContext context) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: user ? C.dark : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(user ? 18 : 4),
          bottomRight: Radius.circular(user ? 4 : 18),
        ),
      ),
      child: typing
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: TypingDots(),
            )
          : SelectableText(
              teks,
              style: TextStyle(
                color: user ? Colors.white : (muted ? C.muted : C.text),
                height: 1.4,
              ),
            ),
    ),
  );
}
