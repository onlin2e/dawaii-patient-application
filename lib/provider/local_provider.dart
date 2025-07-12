import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider with ChangeNotifier {
  String _currentLanguage = 'en';

  LocaleProvider() {
    _loadLanguage(); 
  }

  String get currentLanguage => _currentLanguage;

  // تحميل اللغة من SharedPreferences
  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString('language') ?? 'ar'; 
    notifyListeners();
  }

  // تغيير اللغة وحفظها في SharedPreferences
  Future<void> changeLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = language;
    await prefs.setString('language', language); // حفظ اللغة
    notifyListeners();
  }
}