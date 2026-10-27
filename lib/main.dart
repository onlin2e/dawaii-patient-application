import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:med_ad_app/root/app_root.dart';
import 'package:med_ad_app/services/device_registration.dart';
import 'package:med_ad_app/services/local_reminders.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/// Runs when a push arrives while the app is in the background / closed.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // A message WITH a "notification" part is already shown by the system.
  // Showing it again here produced duplicate notifications on Android.
  if (message.notification != null) return;
  await setupFlutterNotifications();
  showFlutterNotification(message);
}

late AndroidNotificationChannel channel;
bool isFlutterLocalNotificationsInitialized = false;
late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

Future<void> setupFlutterNotifications() async {
  if (isFlutterLocalNotificationsInitialized) return;

  channel = const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin.initialize(
    InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: LocalReminders.darwinSettings,
    ),
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: doseActionBackgroundHandler,
  );
  await LocalReminders.createAndroidChannel(flutterLocalNotificationsPlugin);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // iOS: show pushes as banners even when the app is open.
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  isFlutterLocalNotificationsInitialized = true;
}

/// Title / body for a message – also works for data-only messages.
(String, String)? _textOf(RemoteMessage message) {
  final n = message.notification;
  if (n?.title != null || n?.body != null) {
    return (n?.title ?? 'دوائي', n?.body ?? '');
  }
  final d = message.data;
  if (d['title'] != null || d['body'] != null) {
    return ('${d['title'] ?? 'دوائي'}', '${d['body'] ?? ''}');
  }
  final name = d['medicineName'] ?? 'الدواء';
  switch (d['source']) {
    case 'medicine_reminder':
      return ('تذكير بالدواء', '$name حان موعد أخذ الدواء الآن.');
    case 'medicine_followup':
      return ('تذكير متكرر بالدواء', '$name: تذكير إضافي');
  }
  return null;
}

/// Shows a local notification (Android only – iOS shows pushes itself).
void showFlutterNotification(RemoteMessage message) {
  if (kIsWeb || !Platform.isAndroid) return;
  final text = _textOf(message);
  if (text == null) return;
  flutterLocalNotificationsPlugin.show(
    message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    text.$1,
    text.$2,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

/// Shows short messages (e.g. "dose recorded") from anywhere.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Tap on a local notification / its button while the app is running
/// (iOS: also when the button opened the app).
Future<void> _onNotificationResponse(NotificationResponse response) async {
  try {
    final msg = await LocalReminders.handleResponse(response);
    if (msg != null) {
      appMessengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.right)));
      calculateAndSaveDailyPerformance();
    }
  } catch (e) {
    debugPrint('Notification response failed: $e');
  }
}

/// Re-schedules the on-phone dose reminders (safe to call often).
void refreshLocalReminders() {
  if (kIsWeb || !isFlutterLocalNotificationsInitialized) return;
  LocalReminders.requestReschedule(flutterLocalNotificationsPlugin);
}

// ---------------------------------------------------------------------------
// Daily performance (shown in the Tracker tab)
// ---------------------------------------------------------------------------

/// How many past days are recalculated on each app start. Before, EVERY day
/// since the first log was recalculated with one read per dose, every time
/// the app opened or a notification arrived (thousands of reads, slow).
const int _performanceDays = 60;

bool _performanceRunning = false;

/// Recalculates DailyPerformances for the last [_performanceDays] days.
/// Uses the same dose ids the Home screen writes when the patient confirms:
/// `<medicineId>_<local scheduled time in ms>` built from `nowTime`.
Future<void> calculateAndSaveDailyPerformance() async {
  if (_performanceRunning) return;
  _performanceRunning = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString('patientId');
    if (patientId == null || patientId.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final patientRef = db.collection('ActivePatient').doc(patientId);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDay = today.subtract(const Duration(days: _performanceDays - 1));

    final meds = await patientRef.collection('PatientMedicine').get();

    // day -> [scheduled, taken]
    final totals = <String, List<int>>{};

    for (final med in meds.docs) {
      final data = med.data();
      final start = data['StartDate'];
      final end = data['EndDate'];
      if (start is! Timestamp || end is! Timestamp) continue;
      final List<dynamic> times =
          (data['nowTime'] as List?) ?? (data['MedicineTime'] as List?) ?? const [];
      if (times.isEmpty) continue;

      final startDay = DateTime(
          start.toDate().year, start.toDate().month, start.toDate().day);
      final endDay =
          DateTime(end.toDate().year, end.toDate().month, end.toDate().day);

      // all taken logs of this medicine in the window – ONE query
      final logs = await patientRef
          .collection('PatientMedicine')
          .doc(med.id)
          .collection('MedicineIntakeLogs')
          .where('scheduledTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
          .get();
      final takenIds = logs.docs
          .where((d) => d.data()['taken'] == true)
          .map((d) => d.id)
          .toSet();

      for (var day = firstDay;
          !day.isAfter(today);
          day = DateTime(day.year, day.month, day.day + 1)) {
        if (day.isBefore(startDay) || day.isAfter(endDay)) continue;
        final key = DateFormat('yyyy-MM-dd').format(day);
        for (final t in times) {
          final parts = t.toString().split(':');
          if (parts.length < 2) continue;
          final h = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          if (h == null || m == null) continue;
          final at = DateTime(day.year, day.month, day.day, h, m);
          if (at.isAfter(now)) continue; // not due yet
          final entry = totals.putIfAbsent(key, () => [0, 0]);
          entry[0]++;
          if (takenIds.contains('${med.id}_${at.millisecondsSinceEpoch}')) {
            entry[1]++;
          }
        }
      }
    }

    final batch = db.batch();
    totals.forEach((key, v) {
      final day = DateTime.parse(key);
      batch.set(
        patientRef.collection('DailyPerformances').doc(key),
        {
          'totalScheduled': v[0],
          'excellent': v[1],
          'poor': v[0] - v[1],
          'dailyPercentage': v[0] == 0 ? 0.0 : v[1] * 100.0 / v[0],
          'date': Timestamp.fromDate(day),
        },
        SetOptions(merge: true),
      );
    });
    await batch.commit();
  } catch (e) {
    debugPrint('Error calculating daily performance: $e');
  } finally {
    _performanceRunning = false;
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  try {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  } catch (e) {
    debugPrint('requestPermission failed: $e');
  }

  if (!kIsWeb) {
    await setupFlutterNotifications();
  }

  // Foreground messages: Android does not show them by itself.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    showFlutterNotification(message);
    calculateAndSaveDailyPerformance();
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    calculateAndSaveDailyPerformance();
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: const AppRoot(),
    ),
  );

  // Not awaited – must never delay the first screen.
  DeviceRegistration.sync();
  calculateAndSaveDailyPerformance();
  refreshLocalReminders();

  // iOS: the "أخذت الدواء" button opened the app from a closed state.
  if (!kIsWeb) {
    try {
      final launch =
          await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        // wait for the first screen so the message can be shown
        Future.delayed(const Duration(seconds: 4),
            () => _onNotificationResponse(response));
      }
    } catch (e) {
      debugPrint('launch details failed: $e');
    }
  }
}
