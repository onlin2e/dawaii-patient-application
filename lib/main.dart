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

  String? title = notification?.title;
  String? body = notification?.body;

  // إذا لم تكن هناك بيانات notification مباشرة، حاول استخدام data payload
  // هذا الجزء مهم جداً بعد تعديل وظيفة Firebase لإرسال 'data'
  if (title == null && body == null) {
    title = message.data['title'] ?? 'Med Ad Notification!';
    body = message.data['body'] ?? 'This notification was created via FCM!';
  }

  print('[showFlutterNotification] Attempting to show Flutter notification...');
  print('[showFlutterNotification] Final Title: ${title ?? "No Title"} - Final Body: ${body ?? "No Body"}');
  print('[showFlutterNotification] Received Android Details: Channel ID: ${android?.channelId}, Icon: ${android?.smallIcon}');
  print('[showFlutterNotification] Is kIsWeb: $kIsWeb');

  if (title != null && body != null && !kIsWeb) { // الشرط تغير ليعتمد على title و body وليس notification object
    print('[showFlutterNotification] Conditions met. Displaying notification...');
    flutterLocalNotificationsPlugin.show(
      notification?.hashCode ?? 0, // استخدم hashCode من notification أو 0 إذا كان null
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

/// يمثل أداء المريض اليومي في تناول الدواء.
class DailyPerformance {
  /// إجمالي عدد الجرعات المجدولة لهذا اليوم.
  int totalScheduled = 0;

  /// عدد الجرعات التي تم أخذها بنجاح (فقط "أُخذت").
  int excellent = 0;

  /// عدد الجرعات التي لم يتم أخذها أو تم تفويتها.
  int poor = 0;

  /// النسبة المئوية للالتزام اليومي (الجرعات المأخوذة / الإجمالي).
  double dailyPercentage = 0.0;

  /// التاريخ الذي يمثله هذا الأداء.
  DateTime date;

  DailyPerformance({
    this.totalScheduled = 0,
    this.excellent = 0,
    this.poor = 0,
    this.dailyPercentage = 0.0,
    required this.date,
  });

  /// يحول كائن DailyPerformance إلى Map ليتم حفظه في Firestore.
  Map<String, dynamic> toJson() {
    return {
      'totalScheduled': totalScheduled,
      'excellent': excellent,
      'poor': poor,
      'dailyPercentage': dailyPercentage,
      'date': date.toIso8601String(), // حفظ التاريخ كـ String لسهولة القراءة
    };
  }

  /// ينشئ كائن DailyPerformance من بيانات Map (من Firestore).
  factory DailyPerformance.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    // محاولة قراءة التاريخ كـ Timestamp أولاً، ثم كـ String إذا فشل
    if (json['date'] is Timestamp) {
      parsedDate = (json['date'] as Timestamp).toDate();
    } else if (json['date'] is String) {
      parsedDate = DateTime.parse(json['date']);
    } else {
      // تعيين تاريخ اليوم كقيمة افتراضية إذا كان الحقل غير موجود أو غير صالح
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

/// دالة لحساب وحفظ أداء المريض اليومي في تناول الدواء.
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

    // مرجع لمجموعة DailyPerformances الخاصة بالمريض
    CollectionReference performanceCollection = firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('DailyPerformances');

    DateTime? firstDay;

    // جلب جميع الأدوية الخاصة بالمريض أولاً.
    QuerySnapshot patientMedicineSnapshot = await firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('PatientMedicine')
        .get();

    if (patientMedicineSnapshot.docs.isNotEmpty) {
      // البحث عن أقدم وقت مجدول لجرعة دواء عبر جميع سجلات تناول الأدوية لهذا المريض.
      // هذا يضمن أننا نبدأ الحساب من أول يوم بدأ فيه المريض العلاج.
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

    // إذا لم يتم العثور على سجلات تناول دواء، ابدأ الحساب من اليوم الحالي.
    if (firstDay == null) {
      print('No medicine intake logs found for patient. Cannot calculate performance. Starting from today.');
      firstDay = startOfDay;
    } else {
      // التأكد من أن firstDay هو بداية اليوم (إزالة معلومات الوقت).
      firstDay = DateTime(firstDay.year, firstDay.month, firstDay.day);
    }

    // التكرار عبر كل يوم من أول يوم علاج حتى اليوم الحالي.
    for (DateTime currentDate = firstDay;
        !currentDate.isAfter(today);
        currentDate = currentDate.add(const Duration(days: 1))) {
      DateTime currentDayStart =
          DateTime(currentDate.year, currentDate.month, currentDate.day);
      String currentDayString = DateFormat('yyyy-MM-dd').format(currentDayStart);

      // تهيئة كائن DailyPerformance لليوم الحالي.
      DailyPerformance dailyPerformance = DailyPerformance(date: currentDayStart);

      // إعادة تعيين العدادات لضمان حساب جديد لكل يوم.
      dailyPerformance.totalScheduled = 0;
      dailyPerformance.excellent = 0;
      dailyPerformance.poor = 0;

      // التكرار عبر جميع أدوية المريض النشطة.
      for (final medicineDoc in patientMedicineSnapshot.docs) {
        final Map<String, dynamic>? medicineData = medicineDoc.data() as Map<String, dynamic>?;

        // تخطي الدواء إذا كانت بياناته فارغة.
        if (medicineData == null) {
          print('DEBUG: medicineData is null for doc ID: ${medicineDoc.id}. Skipping.');
          continue;
        }

        final List<dynamic>? medicineTimes = medicineData['MedicineTime'];
        final Timestamp? medicineStartDate = medicineData['StartDate'];
        final Timestamp? medicineEndDate = medicineData['EndDate'];

        // تخطي الدواء إذا كانت البيانات الأساسية (أوقات/تواريخ) مفقودة.
        if (medicineTimes == null || medicineStartDate == null || medicineEndDate == null) {
          print('DEBUG: Missing essential medicine data (times/dates) for doc ID: ${medicineDoc.id}. Skipping.');
          continue;
        }

        final DateTime medStartDay = DateTime(medicineStartDate.toDate().year, medicineStartDate.toDate().month, medicineStartDate.toDate().day);
        final DateTime medEndDay = DateTime(medicineEndDate.toDate().year, medicineEndDate.toDate().month, medicineEndDate.toDate().day);

        // التحقق مما إذا كان اليوم الحالي يقع ضمن فترة علاج الدواء.
        if (!currentDayStart.isBefore(medStartDay) && !currentDayStart.isAfter(medEndDay)) {
          for (final time in medicineTimes) {
            final List<String> parts = time.split(':');
            final int hour = int.parse(parts[0]);
            final int minute = int.parse(parts[1]);

            // ***** التعديل هنا: إنشاء scheduledDateTime ليتطابق مع ID المستند في Firestore *****
            // بما أن Firestore يخزن Timestamp بتوقيت UTC، فيجب أن يكون الجزء الذي يشكل الـ ID بتوقيت UTC.
            // الـ scheduledTime في Firestore هو "21 July 2025 at 19:44:00 UTC+4".
            // هذا يعني أنه 15:44:00 UTC. لذا يجب أن ننشئ الـ DateTime كـ UTC مباشرة.
            final DateTime scheduledDateTimeForId = DateTime.utc(
                currentDayStart.year,
                currentDayStart.month,
                currentDayStart.day,
                hour,
                minute);
            // **********************************************************************************

            // بناء معرف مستند سجل التناول المتوقع باستخدام توقيت UTC
            final String intakeLogDocId = '${medicineDoc.id}_${scheduledDateTimeForId.millisecondsSinceEpoch}';

            // ***** DEBUGGING PRINT STATEMENTS *****
            print('--- Processing for ${DateFormat('yyyy-MM-dd HH:mm').format(scheduledDateTimeForId.toLocal())} (Local Time Display) ---');
            print('DEBUG: Attempting to fetch log for medicineDoc.id: ${medicineDoc.id}');
            print('DEBUG: Scheduled Date Time (UTC used for ID): $scheduledDateTimeForId (Epoch: ${scheduledDateTimeForId.millisecondsSinceEpoch})');
            print('DEBUG: Constructed intakeLogDocId: $intakeLogDocId');
            // ***************************************

            // جلب سجل تناول الدواء المحدد.
            final DocumentSnapshot intakeLogSnapshot = await firestore
                .collection('ActivePatient')
                .doc(patientId)
                .collection('PatientMedicine')
                .doc(medicineDoc.id)
                .collection('MedicineIntakeLogs')
                .doc(intakeLogDocId)
                .get();

            dailyPerformance.totalScheduled++; // زيادة إجمالي الجرعات المجدولة.

            if (intakeLogSnapshot.exists) {
                print('DEBUG: Intake log snapshot EXISTS for ID: $intakeLogDocId');
                final Map<String, dynamic>? logDataFromSnapshot = intakeLogSnapshot.data() as Map<String, dynamic>?;

                if (logDataFromSnapshot != null) {
                    print('DEBUG: Log data: $logDataFromSnapshot');
                    // ***** منطق التصنيف الجديد: Excellent (مأخوذ) أو Poor (لم يؤخذ) *****
                    if (logDataFromSnapshot['taken'] == true) {
                        dailyPerformance.excellent++;
                        print('DEBUG: Dose marked as EXCELLENT (taken: true).');
                    } else {
                        dailyPerformance.poor++;
                        print('DEBUG: Dose marked as POOR (taken: false).');
                    }
                    // ******************************************************************
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

      // حساب النسبة المئوية للالتزام بناءً على الجرعات Excellent.
      dailyPerformance.dailyPercentage = dailyPerformance.totalScheduled > 0
          ? (dailyPerformance.excellent / dailyPerformance.totalScheduled) * 100
          : 0.0;

      // حفظ الأداء اليومي في Firestore.
      await performanceCollection
          .doc(currentDayString)
          .set(dailyPerformance.toJson(), SetOptions(merge: true));

      print(
          'Daily performance saved for $currentDayString: ${dailyPerformance.dailyPercentage.toStringAsFixed(2)}%. '
          'Total Scheduled: ${dailyPerformance.totalScheduled}, Taken: ${dailyPerformance.excellent}, Not Taken: ${dailyPerformance.poor}');
      print('----------------------------------------------------'); // فاصل لسهولة القراءة
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

  // حساب وحفظ الأداء عند بدء التطبيق ويوميًا.
  _calculateAndSaveDailyPerformance(); // الحساب الأولي
  Timer.periodic(const Duration(days: 1), (timer) {
    _calculateAndSaveDailyPerformance(); // إعادة الحساب كل 24 ساعة
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: const AppRoot(),
    ),
  );
}