import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:med_ad_app/screens/home_screen.dart';
import 'package:med_ad_app/services/device_registration.dart';
import 'package:med_ad_app/theme/app_theme.dart';
import 'package:med_ad_app/main.dart' show refreshLocalReminders;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final String testPassword = 'appletest12345';
  final String testName = 'appletest';
  final String testPhone = '95511067';

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? patientId = prefs.getString('patientId');

    if (patientId != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    }
  }

/// Getting the push token must never block login (on iOS it throws when
/// APNs is not ready yet). DeviceRegistration.sync() retries afterwards.
Future<String?> _safeToken() async {
  try {
    return await FirebaseMessaging.instance
        .getToken()
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('getToken failed at login: $e');
    return null;
  }
}

Future<void> login() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isLoading = true;
  });

  String name = nameController.text.trim();
  String phone = phoneController.text.trim();
  String password = passwordController.text.trim();

  try {

    // Test account
    if (password == testPassword) {
      String? deviceToken = await _safeToken();

      await FirebaseFirestore.instance
          .collection('ActivePatient')
          .doc(testPassword)
          .set(
        {
          'patientId': testPassword,
          'patientName': testName,
          'patientPhone': testPhone,
          if (deviceToken != null) 'deviceToken': deviceToken,
        },
        SetOptions(merge: true),
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('patientId', testPassword);
      DeviceRegistration.sync();
      refreshLocalReminders();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );

      return;
    }

    // Check patient exists in AddPatient
    var querySnapshot = await FirebaseFirestore.instance
        .collection('AddPatient')
        .where('id', isEqualTo: password)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      String? deviceToken = await _safeToken();

      await FirebaseFirestore.instance
          .collection('ActivePatient')
          .doc(password)
          .set(
        {
          'patientId': password,
          'patientName': name,
          'patientPhone': phone,
          if (deviceToken != null) 'deviceToken': deviceToken,
        },
        SetOptions(merge: true),
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('patientId', password);
      DeviceRegistration.sync();
      refreshLocalReminders();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرمز السري غير صحيح.'),
        ),
      );
    }
  } catch (e) {
    debugPrint('Login Error: $e');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('حدث خطأ، يرجى المحاولة مرة أخرى.'),
      ),
    );
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String hint, IconData icon) => InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.primary),
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                          color: AppColors.primaryTint, shape: BoxShape.circle),
                      child: Image.asset('assets/2812649.png', fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('مرحبًا بك في دوائي',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                  const SizedBox(height: 6),
                  const Text('سجّل الدخول للمتابعة',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: AppColors.textMuted)),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: nameController,
                    decoration: field('الاسم', Icons.person_outline),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'يرجى إدخال الاسم' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: field('رقم الهاتف', Icons.phone_outlined),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'يرجى إدخال رقم الهاتف';
                      if (value.length != 8) return 'يجب أن يتكون رقم الهاتف من 8 أرقام';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: field('الرمز السري', Icons.lock_outline),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'يرجى إدخال الرمز السري' : null,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _isLoading ? null : login,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : const Text('تسجيل الدخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
