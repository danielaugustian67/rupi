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
    channelDescription: 'Pengingat catat keuangan & tenggat menu',
    importance: Importance.high,
  ),
  iOS: DarwinNotificationDetails(),
);

/// ID notifikasi: 1 = pengingat harian, 1000+id = tenggat item menu.
const _idHarian = 1;
int idTempo(int itemId) => 1000 + itemId;

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

/// Jadwalkan ulang pengingat tenggat untuk item menu yang belum lunas.
Future<void> jadwalTempo(List<Map<String, dynamic>> items) async {
  if (!_siap) return;
  final pending = await _plugin.pendingNotificationRequests();
  for (final p in pending) {
    if (p.id >= 1000) await _plugin.cancel(id: p.id);
  }
  final now = DateTime.now();
  for (final u in items) {
    final tempo = u['tenggat'] as String?;
    if (tempo == null) continue;
    final w = waktuTempo(tempo, now);
    if (w == null) continue;
    await _plugin.zonedSchedule(
      id: idTempo((u['id'] as num).toInt()),
      title: 'Tenggat hari ini',
      body: '${u['judul']}: ${rp(u['nominal'] as num)}',
      scheduledDate: tz.TZDateTime.from(w, tz.local),
      notificationDetails: _detail,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

/// Notifikasi tgl 1 jam 09:00 berisi ringkasan bulan yang baru lewat.
/// shortcut: isinya dari data saat app terakhir dibuka bulan itu; transaksi
/// setelahnya tidak ikut. Upgrade ke push dari server kalau perlu akurat.
Future<void> jadwalRingkasan(
  DateTime bulan,
  int masuk,
  int keluar,
  String? terbesar,
) async {
  if (!_siap) return;
  final t = tz.TZDateTime(tz.local, bulan.year, bulan.month + 1, 1, 9);
  await _plugin.zonedSchedule(
    id: _idRingkasan,
    title: 'Ringkasan ${namaBulan[bulan.month - 1]}',
    body:
        'Masuk ${rp(masuk)}, keluar ${rp(keluar)}, selisih ${rp(masuk - keluar)}'
        '${terbesar == null ? '' : '. Terbesar: $terbesar'}',
    scheduledDate: t,
    notificationDetails: _detail,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

const _idRingkasan = 2;

const namaBulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
