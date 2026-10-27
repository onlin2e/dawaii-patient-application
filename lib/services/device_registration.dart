import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the patient's push token up to date in Firestore.
///
/// Before: the token was saved ONLY at login. FCM tokens change (app update,
/// restore, token rotation, reinstall without logout…), so many patients
/// kept an old token in ActivePatient and silently stopped receiving the
/// server reminders.
///
/// Now: on every app start and whenever FCM rotates the token we write the
/// current token, plus `lastOpenedAt` so the admin can see who opens the app.
class DeviceRegistration {
  static const String appVersion = '1.0.7+19';
  static StreamSubscription<String>? _refreshSub;

  static Future<String?> _currentToken() async {
    final messaging = FirebaseMessaging.instance;
    if (!kIsWeb && Platform.isIOS) {
      // On iOS the FCM token is only available after APNs registered.
      String? apns = await messaging.getAPNSToken();
      for (var i = 0; apns == null && i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        apns = await messaging.getAPNSToken();
      }
      if (apns == null) return null;
    }
    return messaging.getToken();
  }

  static Future<void> _write(String patientId, String? token) async {
    final data = <String, dynamic>{
      'lastOpenedAt': FieldValue.serverTimestamp(),
      'appVersion': appVersion,
      // NOTE: not "devicePlatform" – the server sends data-only messages
      // when devicePlatform == 'android'.
      'deviceOS': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
    };
    if (token != null && token.isNotEmpty) {
      data['deviceToken'] = token;
      data['deviceUpdatedAt'] = FieldValue.serverTimestamp();
    }
    await FirebaseFirestore.instance
        .collection('ActivePatient')
        .doc(patientId)
        .set(data, SetOptions(merge: true));
  }

  /// Call after Firebase.initializeApp and after login. Never throws.
  static Future<void> sync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getString('patientId');
      if (patientId == null || patientId.isEmpty) return;

      final token = await _currentToken().timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
      await _write(patientId, token);

      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) async {
          try {
            final p = await SharedPreferences.getInstance();
            final id = p.getString('patientId');
            if (id != null && id.isNotEmpty) await _write(id, newToken);
          } catch (e) {
            debugPrint('Token refresh save failed: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('DeviceRegistration.sync failed: $e');
    }
  }
}
