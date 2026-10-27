import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:med_ad_app/firebase_options.dart';

/// Dose reminders scheduled ON THE PHONE, with a "أخذت الدواء" button.
///
/// * The phone shows the reminder at the exact dose time even without
///   internet, and the patient can record the dose from the notification.
/// * The 3-hour rule is kept: a dose can only be recorded from
///   1 minute before until 3 hours after its time (same as the Home screen).
/// * The app tells the server until when it has reminders scheduled
///   (`localRemindersUntil`), so the server does not send a second reminder
///   at the same time. Server follow-ups (30 min, 1 h, 2.5 h) still arrive
///   if the dose was not recorded.
class LocalReminders {
  static const String actionTaken = 'TAKEN';
  static const String iosCategory = 'DOSE_ACTIONS';
  static const String _payloadPrefix = 'dose|';
  static const Duration recordWindow = Duration(hours: 3);
  static const int _daysAhead = 7;
  static const int _maxScheduled = 60; // iOS allows 64 pending notifications

  static const AndroidNotificationChannel doseChannel =
      AndroidNotificationChannel(
    'dose_reminders',
    'تذكير الجرعات',
    description: 'تذكير بموعد الدواء مع زر تسجيل الجرعة',
    importance: Importance.max,
  );

  static bool _running = false;
  static Timer? _debounce;

  // ------------------------------------------------------------ settings

  static DarwinInitializationSettings get darwinSettings =>
      DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            iosCategory,
            actions: [
              DarwinNotificationAction.plain(
                actionTaken,
                'أخذت الدواء ✅',
                // opens the app briefly so the dose is saved reliably
                options: {DarwinNotificationActionOption.foreground},
              ),
            ],
          ),
        ],
      );

  static Future<void> createAndroidChannel(
      FlutterLocalNotificationsPlugin plugin) async {
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(doseChannel);
  }

  // ------------------------------------------------------------ payload

  static String _payload(String patientId, String medicineId, DateTime at) =>
      '$_payloadPrefix$patientId|$medicineId|${at.millisecondsSinceEpoch}';

  static int _notificationId(String medicineId, DateTime at) =>
      (medicineId.hashCode ^ (at.millisecondsSinceEpoch ~/ 60000)) &
      0x7fffffff;

  // ------------------------------------------------------------ recording

  /// Handles a tap on a dose notification or its button. Returns a message
  /// for the user (or null when nothing to say).
  static Future<String?> handleResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || !payload.startsWith(_payloadPrefix)) return null;
    // A plain tap just opens the app (the Home screen shows the dose).
    if (response.actionId != actionTaken) return null;

    final parts = payload.substring(_payloadPrefix.length).split('|');
    if (parts.length != 3) return null;
    final patientId = parts[0];
    final medicineId = parts[1];
    final ms = int.tryParse(parts[2]);
    if (ms == null) return null;
    return recordTaken(
      patientId: patientId,
      medicineId: medicineId,
      scheduled: DateTime.fromMillisecondsSinceEpoch(ms),
      source: 'notification_action',
    );
  }

  /// Saves a taken dose if it is inside the allowed window.
  static Future<String> recordTaken({
    required String patientId,
    required String medicineId,
    required DateTime scheduled,
    String source = 'app',
  }) async {
    final now = DateTime.now();
    final opens = scheduled.subtract(const Duration(minutes: 1));
    final closes = scheduled.add(recordWindow);
    if (now.isBefore(opens)) return 'لم يحن موعد هذه الجرعة بعد.';
    if (!now.isBefore(closes)) {
      return 'انتهى وقت تسجيل هذه الجرعة (3 ساعات من موعدها).';
    }

    final docId = '${medicineId}_${scheduled.millisecondsSinceEpoch}';
    await FirebaseFirestore.instance
        .collection('ActivePatient')
        .doc(patientId)
        .collection('PatientMedicine')
        .doc(medicineId)
        .collection('MedicineIntakeLogs')
        .doc(docId)
        .set({
      'scheduledTime': Timestamp.fromDate(scheduled),
      'takenAt': Timestamp.fromDate(now),
      'takenBy': patientId,
      'taken': true,
      'source': source,
    }, SetOptions(merge: true));
    return 'تم تسجيل أخذ الدواء ✅';
  }

  // ------------------------------------------------------------ scheduling

  /// Re-schedules the next doses. Safe to call often (debounced).
  static void requestReschedule(FlutterLocalNotificationsPlugin plugin) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => reschedule(plugin));
  }

  static Future<void> reschedule(FlutterLocalNotificationsPlugin plugin) async {
    if (kIsWeb || _running) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getString('patientId');
      if (patientId == null || patientId.isEmpty) return;

      final db = FirebaseFirestore.instance;
      final patientRef = db.collection('ActivePatient').doc(patientId);
      final meds = await patientRef.collection('PatientMedicine').get();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastDay = today.add(const Duration(days: _daysAhead));

      // collect upcoming doses
      final doses = <({String medId, String name, String pills, DateTime at})>[];
      for (final med in meds.docs) {
        final d = med.data();
        final start = d['StartDate'];
        final end = d['EndDate'];
        if (start is! Timestamp || end is! Timestamp) continue;
        final times =
            (d['nowTime'] as List?) ?? (d['MedicineTime'] as List?) ?? const [];
        final s = start.toDate();
        final e = end.toDate();
        final startDay = DateTime(s.year, s.month, s.day);
        final endDay = DateTime(e.year, e.month, e.day);
        for (var day = today;
            !day.isAfter(lastDay);
            day = DateTime(day.year, day.month, day.day + 1)) {
          if (day.isBefore(startDay) || day.isAfter(endDay)) continue;
          for (final t in times) {
            final p = t.toString().split(':');
            if (p.length < 2) continue;
            final h = int.tryParse(p[0]);
            final m = int.tryParse(p[1]);
            if (h == null || m == null) continue;
            final at = DateTime(day.year, day.month, day.day, h, m);
            if (!at.isAfter(now)) continue;
            doses.add((
              medId: med.id,
              name: '${d['MedicineName'] ?? 'الدواء'}',
              pills: '${d['NumberOfPillsPerDose'] ?? ''}',
              at: at,
            ));
          }
        }
      }
      doses.sort((a, b) => a.at.compareTo(b.at));
      final chosen = doses.take(_maxScheduled).toList();

      // cancel our previously scheduled doses
      final pending = await plugin.pendingNotificationRequests();
      for (final r in pending) {
        if ((r.payload ?? '').startsWith(_payloadPrefix)) {
          await plugin.cancel(r.id);
        }
      }

      var mode = AndroidScheduleMode.inexactAllowWhileIdle;
      if (Platform.isAndroid) {
        final android = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final exact = await android?.canScheduleExactNotifications() ?? false;
        if (exact) mode = AndroidScheduleMode.exactAllowWhileIdle;
      }

      DateTime? lastScheduled;
      for (final dose in chosen) {
        final pillsText = dose.pills.isEmpty ? '' : ' (${dose.pills} حبة)';
        await plugin.zonedSchedule(
          _notificationId(dose.medId, dose.at),
          'تذكير بالدواء',
          '${dose.name}$pillsText — حان موعد الجرعة. اضغط "أخذت الدواء" بعد أخذها.',
          tz.TZDateTime.from(dose.at, tz.UTC),
          NotificationDetails(
            android: AndroidNotificationDetails(
              doseChannel.id,
              doseChannel.name,
              channelDescription: doseChannel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              category: AndroidNotificationCategory.reminder,
              actions: const [
                AndroidNotificationAction(
                  actionTaken,
                  'أخذت الدواء ✅',
                  showsUserInterface: false,
                  cancelNotification: true,
                ),
              ],
            ),
            iOS: const DarwinNotificationDetails(
              categoryIdentifier: iosCategory,
              presentAlert: true,
              presentSound: true,
              presentBanner: true,
            ),
          ),
          androidScheduleMode: mode,
          payload: _payload(patientId, dose.medId, dose.at),
        );
        lastScheduled = dose.at;
      }

      // Tell the server which reminders the phone already covers.
      await patientRef.set({
        'localRemindersUntil': lastScheduled == null
            ? FieldValue.delete()
            : Timestamp.fromDate(lastScheduled),
        'localRemindersSyncedAt': FieldValue.serverTimestamp(),
        'localRemindersCount': chosen.length,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('LocalReminders.reschedule failed: $e');
    } finally {
      _running = false;
    }
  }
}

/// Runs in a background isolate when the "أخذت الدواء" button is pressed on
/// Android while the app is closed.
@pragma('vm:entry-point')
Future<void> doseActionBackgroundHandler(NotificationResponse response) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    }
    final msg = await LocalReminders.handleResponse(response);
    if (msg != null && msg.startsWith('انتهى')) {
      // Let the patient know it was not recorded.
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 & 0x7fffffff,
        'لم يتم التسجيل',
        msg,
        NotificationDetails(
          android: AndroidNotificationDetails(
            LocalReminders.doseChannel.id,
            LocalReminders.doseChannel.name,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  } catch (e) {
    debugPrint('doseActionBackgroundHandler failed: $e');
  }
}
