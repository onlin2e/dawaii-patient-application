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
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'firebase_options.dart';
import 'package:intl/intl.dart';

// معالجة الإشعارات في الخلفية
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await setupFlutterNotifications();
  showFlutterNotification(message);
  print('Handling a background message: ${message.messageId}');
}

// إنشاء قناة إشعارات Android
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
  if (notification != null && android != null && !kIsWeb) {
    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: 'assets/ic_launcher_adaptive_fore.png',
        ),
      ),
    );
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
  int moderate = 0;
  int poor = 0;
  double dailyPercentage = 0.0;
  DateTime date;

  DailyPerformance({
    this.totalScheduled = 0,
    this.excellent = 0,
    this.moderate = 0,
    this.poor = 0,
    this.dailyPercentage = 0.0,
    required this.date, 
  });

  Map<String, dynamic> toJson() {
    return {
      'totalScheduled': totalScheduled,
      'excellent': excellent,
      'moderate': moderate,
      'poor': poor,
      'dailyPercentage': dailyPercentage,
      'date': date,
    };
  }

  factory DailyPerformance.fromJson(Map<String, dynamic> json) {
    return DailyPerformance(
      totalScheduled: json['totalScheduled'] ?? 0,
      excellent: json['excellent'] ?? 0,
      moderate: json['moderate'] ?? 0,
      dailyPercentage: json['dailyPercentage'] ?? 0.0,
      date: (json['date'] as Timestamp).toDate(), 
    );
  }
}

// Function to calculate and save daily performance
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
    String todayString = DateFormat('yyyy-MM-dd').format(startOfDay);

    // Collection reference for DailyPerformances
    CollectionReference performanceCollection = firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('DailyPerformances');

    // Fetch the first day of treatment for this patient.
    QuerySnapshot patientMedicineSnapshot = await firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('PatientMedicine')
        .get();

    DateTime? firstDay;
    if (patientMedicineSnapshot.docs.isNotEmpty) {
      // Get the scheduledTime of the first medicine intake as the start date
      QuerySnapshot firstLogSnapshot = await firestore
          .collection('ActivePatient')
          .doc(patientId)
          .collection('PatientMedicine')
          .doc(patientMedicineSnapshot.docs.first.id)
          .collection('MedicineIntakeLogs')
          .orderBy('scheduledTime', descending: false)
          .limit(1)
          .get();

      if (firstLogSnapshot.docs.isNotEmpty) {
        // Null check here and check the data exists
        final firstLogData = firstLogSnapshot.docs.first.data();
        if (firstLogData != null &&
            firstLogData is Map<String, dynamic> &&
            firstLogData.containsKey('scheduledTime')) {
          firstDay =
              (firstLogData['scheduledTime'] as Timestamp).toDate();
        }
      }
    }

    if (firstDay == null) {
      print(
          'No medicine intake logs found for patient.  Cannot calculate performance.');
      return;
    }

    // Iterate through each day from the first day of treatment until today.
    for (DateTime currentDate = firstDay;
        !currentDate.isAfter(today);
        currentDate = currentDate.add(const Duration(days: 1))) {
      DateTime currentDayStart =
          DateTime(currentDate.year, currentDate.month, currentDate.day);
      String currentDayString = DateFormat('yyyy-MM-dd').format(currentDayStart);

      // Fetch existing performance data for the current day
      DocumentSnapshot performanceSnapshot =
          await performanceCollection.doc(currentDayString).get();

      DailyPerformance dailyPerformance =
          DailyPerformance(date: currentDayStart); // Initialize with the date.

      if (performanceSnapshot.exists) {
        dailyPerformance = DailyPerformance.fromJson(
            performanceSnapshot.data() as Map<String, dynamic>);
      }

      // Fetch medicine intake logs for the current day, THIS IS THE CORRECT WAY
      List<QuerySnapshot> medicineLogsSnapshots = [];
      for (final medicineDoc in patientMedicineSnapshot.docs) {
        final logSnapshot = await firestore
            .collection('ActivePatient')
            .doc(patientId)
            .collection('PatientMedicine')
            .doc(medicineDoc.id) // Use medicineDoc.id to get the ID
            .collection('MedicineIntakeLogs')
            .where('scheduledTime',
                isGreaterThanOrEqualTo: Timestamp.fromDate(currentDayStart))
            .where('scheduledTime',
                isLessThanOrEqualTo: Timestamp.fromDate(
                    currentDayStart.add(const Duration(days: 1))))
            .get();
        medicineLogsSnapshots.add(logSnapshot);
      }

      // Reset counters
      dailyPerformance.totalScheduled = 0;
      dailyPerformance.excellent = 0;
      dailyPerformance.moderate = 0;
      dailyPerformance.poor = 0;

      // Iterate through the logs from all medicines
      for (final logSnapshot in medicineLogsSnapshots) {
        for (var logDoc in logSnapshot.docs) { // Iterate over the documents
          var logData = logDoc.data() as Map<String, dynamic>;
          DateTime scheduledTime =
              (logData['scheduledTime'] as Timestamp).toDate();
          bool taken = logData['taken'] ?? false;
          DateTime? takenAt = logData['takenAt']?.toDate();

          dailyPerformance.totalScheduled++;
          if (taken) {
            if (takenAt != null &&
                takenAt.isBefore(scheduledTime.add(const Duration(hours: 1)))) {
              dailyPerformance.excellent++;
            } else if (takenAt != null &&
                takenAt.isBefore(scheduledTime.add(const Duration(hours: 2)))) {
              dailyPerformance.moderate++;
            } else {
              dailyPerformance.poor++;
            }
          } else {
            dailyPerformance.poor++;
          }
        }
      }

      // Calculate percentage
      dailyPerformance.dailyPercentage =
          dailyPerformance.totalScheduled > 0
              ? (dailyPerformance.excellent * 100 +
                      dailyPerformance.moderate * 50) /
                  (dailyPerformance.totalScheduled * 100)
              : 0.0;

      // Save to Firestore (in DailyPerformances collection)
      await performanceCollection
          .doc(currentDayString)
          .set(dailyPerformance.toJson(), SetOptions(merge: true));
      print(
          'Daily performance saved: ${dailyPerformance.dailyPercentage} for $currentDayString.  Total Scheduled: ${dailyPerformance.totalScheduled}, Excellent: ${dailyPerformance.excellent}, Moderate: ${dailyPerformance.moderate}, Poor: ${dailyPerformance.poor}');
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

  // Calculate and save performance on app start and daily.
  _calculateAndSaveDailyPerformance(); // Initial calculation
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

