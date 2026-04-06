import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:med_ad_app/root/app_root.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:intl/intl.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await setupFlutterNotifications();
  showFlutterNotification(message);
  print('Handling a background message: ${message.messageId}');
}

late AndroidNotificationChannel channel;
bool isFlutterLocalNotificationsInitialized = false;
late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

Future<void> setupFlutterNotifications() async {
  if (isFlutterLocalNotificationsInitialized) {
    return;
  }
  channel = const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  isFlutterLocalNotificationsInitialized = true;
}

void showFlutterNotification(RemoteMessage message) {
  RemoteNotification? notification = message.notification;
  AndroidNotification? android = message.notification?.android;

  String? title = notification?.title;
  String? body = notification?.body;

  if (title == null && body == null) {
    title = message.data['title'] ?? 'Med Ad Notification!';
    body = message.data['body'] ?? 'This notification was created via FCM!';
  }

  print('[showFlutterNotification] Attempting to show Flutter notification...');
  print('[showFlutterNotification] Final Title: ${title ?? "No Title"} - Final Body: ${body ?? "No Body"}');
  print('[showFlutterNotification] Received Android Details: Channel ID: ${android?.channelId}, Icon: ${android?.smallIcon}');
  print('[showFlutterNotification] Is kIsWeb: $kIsWeb');

  if (title != null && body != null && !kIsWeb) {
    print('[showFlutterNotification] Conditions met. Displaying notification...');
    flutterLocalNotificationsPlugin.show(
      notification?.hashCode ?? 0,
      title,
      body,
      NotificationDetails(
  android: AndroidNotificationDetails(
    channel.id,
    channel.name,
    channelDescription: channel.description,
    icon: '@mipmap/ic_launcher',
    priority: Priority.high,
  ),
),
    );
    print('[showFlutterNotification] Notification show method called.');
  } else {
    print('[showFlutterNotification] Conditions NOT met to show notification:');
    print('[showFlutterNotification]   Title is null: ${title == null}');
    print('[showFlutterNotification]   Body is null: ${body == null}');
    print('[showFlutterNotification]   kIsWeb is true: $kIsWeb');
  }
}

int _messageCount = 0;

String constructFCMPayload(String? token) {
  _messageCount++;
  return jsonEncode({
    'token': token,
    'data': {
      'via': 'Med Ad App Cloud Messaging!!!',
      'count': _messageCount.toString(),
    },
    'notification': {
      'title': 'Med Ad Notification!',
      'body': 'This notification (#$_messageCount) was created via FCM!',
    },
  });
}

class DailyPerformance {
  int totalScheduled = 0;

  int excellent = 0;

  int poor = 0;

  double dailyPercentage = 0.0;

  DateTime date;

  DailyPerformance({
    this.totalScheduled = 0,
    this.excellent = 0,
    this.poor = 0,
    this.dailyPercentage = 0.0,
    required this.date,
  });

  Map<String, dynamic> toJson() {
    return {
      'totalScheduled': totalScheduled,
      'excellent': excellent,
      'poor': poor,
      'dailyPercentage': dailyPercentage,
      'date': date.toIso8601String(),
    };
  }

  factory DailyPerformance.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['date'] is Timestamp) {
      parsedDate = (json['date'] as Timestamp).toDate();
    } else if (json['date'] is String) {
      parsedDate = DateTime.parse(json['date']);
    } else {
      parsedDate = DateTime.now();
    }

    return DailyPerformance(
      totalScheduled: json['totalScheduled'] ?? 0,
      excellent: json['excellent'] ?? 0,
      poor: json['poor'] ?? 0,
      dailyPercentage: json['dailyPercentage'] ?? 0.0,
      date: parsedDate,
    );
  }
}

Future<void> _calculateAndSaveDailyPerformance() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? patientId = prefs.getString('patientId');
    if (patientId == null) {
      print('Patient ID is null, cannot calculate performance.');
      return;
    }

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    DateTime today = DateTime.now();
    DateTime startOfDay = DateTime(today.year, today.month, today.day);

    CollectionReference performanceCollection = firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('DailyPerformances');

    DateTime? firstDay;

    QuerySnapshot patientMedicineSnapshot = await firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('PatientMedicine')
        .get();

    if (patientMedicineSnapshot.docs.isNotEmpty) {
      for (final medicineDoc in patientMedicineSnapshot.docs) {
        final QuerySnapshot logSnapshot = await firestore
            .collection('ActivePatient')
            .doc(patientId)
            .collection('PatientMedicine')
            .doc(medicineDoc.id)
            .collection('MedicineIntakeLogs')
            .orderBy('scheduledTime', descending: false)
            .limit(1)
            .get();

        if (logSnapshot.docs.isNotEmpty) {
          final Map<String, dynamic>? logData = logSnapshot.docs.first.data() as Map<String, dynamic>?;

          if (logData != null && logData.containsKey('scheduledTime') && logData['scheduledTime'] is Timestamp) {
            DateTime currentMedicineFirstDay = (logData['scheduledTime'] as Timestamp).toDate();
            if (firstDay == null || currentMedicineFirstDay.isBefore(firstDay)) {
              firstDay = currentMedicineFirstDay;
            }
          } else {
             print('DEBUG: logData is null or missing scheduledTime/Timestamp for medicineDoc ID: ${medicineDoc.id}');
          }
        }
      }
    }

    if (firstDay == null) {
      print('No medicine intake logs found for patient. Cannot calculate performance. Starting from today.');
      firstDay = startOfDay;
    } else {
      firstDay = DateTime(firstDay.year, firstDay.month, firstDay.day);
    }

    for (DateTime currentDate = firstDay;
        !currentDate.isAfter(today);
        currentDate = currentDate.add(const Duration(days: 1))) {
      DateTime currentDayStart =
          DateTime(currentDate.year, currentDate.month, currentDate.day);
      String currentDayString = DateFormat('yyyy-MM-dd').format(currentDayStart);

      DailyPerformance dailyPerformance = DailyPerformance(date: currentDayStart);

      dailyPerformance.totalScheduled = 0;
      dailyPerformance.excellent = 0;
      dailyPerformance.poor = 0;

      for (final medicineDoc in patientMedicineSnapshot.docs) {
        final Map<String, dynamic>? medicineData = medicineDoc.data() as Map<String, dynamic>?;

        if (medicineData == null) {
          print('DEBUG: medicineData is null for doc ID: ${medicineDoc.id}. Skipping.');
          continue;
        }

        final List<dynamic>? medicineTimes = medicineData['MedicineTime'];
        final Timestamp? medicineStartDate = medicineData['StartDate'];
        final Timestamp? medicineEndDate = medicineData['EndDate'];

        if (medicineTimes == null || medicineStartDate == null || medicineEndDate == null) {
          print('DEBUG: Missing essential medicine data (times/dates) for doc ID: ${medicineDoc.id}. Skipping.');
          continue;
        }

        final DateTime medStartDay = DateTime(medicineStartDate.toDate().year, medicineStartDate.toDate().month, medicineStartDate.toDate().day);
        final DateTime medEndDay = DateTime(medicineEndDate.toDate().year, medicineEndDate.toDate().month, medicineEndDate.toDate().day);

        if (!currentDayStart.isBefore(medStartDay) && !currentDayStart.isAfter(medEndDay)) {
          for (final time in medicineTimes) {
            final List<String> parts = time.split(':');
            final int hour = int.parse(parts[0]);
            final int minute = int.parse(parts[1]);

            final DateTime scheduledDateTimeForId = DateTime.utc(
                currentDayStart.year,
                currentDayStart.month,
                currentDayStart.day,
                hour,
                minute);

            final String intakeLogDocId = '${medicineDoc.id}_${scheduledDateTimeForId.millisecondsSinceEpoch}';

            print('--- Processing for ${DateFormat('yyyy-MM-dd HH:mm').format(scheduledDateTimeForId.toLocal())} (Local Time Display) ---');
            print('DEBUG: Attempting to fetch log for medicineDoc.id: ${medicineDoc.id}');
            print('DEBUG: Scheduled Date Time (UTC used for ID): $scheduledDateTimeForId (Epoch: ${scheduledDateTimeForId.millisecondsSinceEpoch})');
            print('DEBUG: Constructed intakeLogDocId: $intakeLogDocId');

            final DocumentSnapshot intakeLogSnapshot = await firestore
                .collection('ActivePatient')
                .doc(patientId)
                .collection('PatientMedicine')
                .doc(medicineDoc.id)
                .collection('MedicineIntakeLogs')
                .doc(intakeLogDocId)
                .get();

            dailyPerformance.totalScheduled++; 
            if (intakeLogSnapshot.exists) {
                print('DEBUG: Intake log snapshot EXISTS for ID: $intakeLogDocId');
                final Map<String, dynamic>? logDataFromSnapshot = intakeLogSnapshot.data() as Map<String, dynamic>?;

                if (logDataFromSnapshot != null) {
                    print('DEBUG: Log data: $logDataFromSnapshot');
                    if (logDataFromSnapshot['taken'] == true) {
                        dailyPerformance.excellent++;
                        print('DEBUG: Dose marked as EXCELLENT (taken: true).');
                    } else {
                        dailyPerformance.poor++;
                        print('DEBUG: Dose marked as POOR (taken: false).');
                    }
                } else {
                    dailyPerformance.poor++;
                    print('DEBUG: Log data is NULL for existing snapshot. Marked as POOR.');
                }
            } else {
              dailyPerformance.poor++;
              print('DEBUG: Intake log snapshot DOES NOT EXIST for ID: $intakeLogDocId. Marked as POOR.');
            }
          }
        }
      }

      dailyPerformance.dailyPercentage = dailyPerformance.totalScheduled > 0
          ? (dailyPerformance.excellent / dailyPerformance.totalScheduled) * 100
          : 0.0;

      await performanceCollection
          .doc(currentDayString)
          .set(dailyPerformance.toJson(), SetOptions(merge: true));

      print(
          'Daily performance saved for $currentDayString: ${dailyPerformance.dailyPercentage.toStringAsFixed(2)}%. '
          'Total Scheduled: ${dailyPerformance.totalScheduled}, Taken: ${dailyPerformance.excellent}, Not Taken: ${dailyPerformance.poor}');
      print('----------------------------------------------------');
    }
  } catch (e) {
    print('Error calculating and saving daily performance: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  await messaging.requestPermission();
  String? token = await messaging.getToken();
  print("Device Token: $token");

  if (!kIsWeb) {
    await setupFlutterNotifications();
  }

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    showFlutterNotification(message);
    _calculateAndSaveDailyPerformance();
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('A new onMessageOpenedApp event was published!');
    _calculateAndSaveDailyPerformance();
  });

  _calculateAndSaveDailyPerformance();
  Timer.periodic(const Duration(days: 1), (timer) {
    _calculateAndSaveDailyPerformance();
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: const AppRoot(),
    ),
  );
}