import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'format.dart';

final _plugin = FlutterLocalNotificationsPlugin();
bool _siap = false;

const _detail = NotificationDetails(
  android: AndroidNotificationDetails(
    'pengingat',
    'Pengingat',
    channelDescription: 'Pengingat catat keuangan & jatuh tempo pinjaman',
    importance: Importance.high,
  ),
  iOS: DarwinNotificationDetails(),
);

/// ID notifikasi: 1 = pengingat harian, 1000+id = jatuh tempo pinjaman.
const _idHarian = 1;
int idTempo(int utangId) => 1000 + utangId;

/// Waktu notifikasi jatuh tempo: jam 09:00 pada [tempo], atau null kalau sudah lewat.
DateTime? waktuTempo(String tempo, DateTime now) {
  final d = DateTime.tryParse(tempo);
  if (d == null) return null;
  final t = DateTime(d.year, d.month, d.day, 9);
  return t.isAfter(now) ? t : null;
}

Future<void> initNotif() async {
  if (_siap) return;
  try {
    tzdata.initializeTimeZones();
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
  }
  // Izin notifikasi diminta di sini (iOS: dialog sekali saja).
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  _siap = true;
  await _harian();
}

/// Tiap hari jam 20:00: ajak mencatat pengeluaran hari ini.
Future<void> _harian() async {
  final now = tz.TZDateTime.now(tz.local);
  var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
  if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
  await _plugin.zonedSchedule(
    id: _idHarian,
    title: 'Sudah catat pengeluaran hari ini?',
    body: 'Ketik singkat saja, AI yang merapikan.',
    scheduledDate: t,
    notificationDetails: _detail,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

/// Jadwalkan ulang pengingat jatuh tempo untuk pinjaman yang masih ada sisa.
Future<void> jadwalTempo(List<Map<String, dynamic>> pinjaman) async {
  if (!_siap) return;
  final pending = await _plugin.pendingNotificationRequests();
  for (final p in pending) {
    if (p.id >= 1000) await _plugin.cancel(id: p.id);
  }
  final now = DateTime.now();
  for (final u in pinjaman) {
    final tempo = u['jatuh_tempo'] as String?;
    if (tempo == null || (u['sisa'] as num) <= 0) continue;
    final w = waktuTempo(tempo, now);
    if (w == null) continue;
    await _plugin.zonedSchedule(
      id: idTempo((u['id'] as num).toInt()),
      title: 'Pinjaman jatuh tempo hari ini',
      body: '${u['nama']}: sisa ${rp(u['sisa'] as num)}',
      scheduledDate: tz.TZDateTime.from(w, tz.local),
      notificationDetails: _detail,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
