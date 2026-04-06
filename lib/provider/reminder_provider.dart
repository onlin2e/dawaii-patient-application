import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

class ReminderProvider extends ChangeNotifier {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Map<String, Timer> _reminderTimers = {};
  Map<String, bool> _isRemindingMap = {};

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon'); // استبدل 'app_icon' باسم أيقونة تطبيقك

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  bool isReminding(String medicineId) {
    return _isRemindingMap[medicineId] ?? false;
  }

  Future<void> scheduleReminder(
    String medicineName,
    String medicineId,
    DateTime scheduledTime,
  ) async {
    if (_isRemindingMap[medicineId] == true) {
      print('تذكير قيد الإعداد بالفعل للدواء: $medicineId');
      return;
    }

    _isRemindingMap[medicineId] = true;
    notifyListeners();

    final now = DateTime.now();
    final reminderTime = scheduledTime.add(const Duration(minutes: 30));
    final difference = reminderTime.difference(now);

    if (difference.inSeconds > 0) {
      _reminderTimers[medicineId] = Timer(difference, () async {
        await _showNotification(medicineName, medicineId);
        _isRemindingMap[medicineId] = false;
        _reminderTimers.remove(medicineId);
        notifyListeners();
      });
      print('تم جدولة تذكير لـ $medicineName بعد 30 دقيقة.');
    } else {
      // إذا كان الوقت قد فات بالفعل، قم بإعادة تفعيل الزر فورًا
      _isRemindingMap[medicineId] = false;
      notifyListeners();
      print('وقت التذكير بعد 30 دقيقة قد فات.');
    }
  }

  Future<void> cancelReminder(String medicineId) async {
    _reminderTimers[medicineId]?.cancel();
    _reminderTimers.remove(medicineId);
    _isRemindingMap[medicineId] = false;
    notifyListeners();
    print('تم إلغاء التذكير لـ $medicineId.');
  }

  Future<void> _showNotification(String medicineName, String medicineId) async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'reminder_channel_id', // معرف فريد للقناة
      'Medicine Reminders', // اسم القناة
      channelDescription: ' تذكيرات بأخذ الدواء', // وصف القناة
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'تذكير بالدواء',
    );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
      0, // معرف الإشعار (يمكن أن يكون فريدًا لكل دواء إذا لزم الأمر)
      'تذكير بالدواء',
      'تذكير بأخذ دواء: $medicineName',
      notificationDetails,
    );
    print('تم عرض إشعار لـ $medicineName.');
  }

  @override
  void dispose() {
    _reminderTimers.values.forEach((timer) => timer.cancel());
    _reminderTimers.clear();
    super.dispose();
  }
}