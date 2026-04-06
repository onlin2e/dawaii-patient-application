import 'package:flutter/material.dart';
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:med_ad_app/screens/medication_screen.dart';
import 'package:med_ad_app/screens/notification_screen.dart';
import 'package:med_ad_app/screens/home_screen_content.dart';
import 'package:med_ad_app/screens/profile_screen.dart';
import 'package:med_ad_app/screens/tracker_screen.dart';
import 'package:provider/provider.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    HomeScreenContent(),
    NotificationsScreen(),
    MyMedScreen(),
    MedicineTrackingScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final currentLanguage = Provider.of<LocaleProvider>(context).currentLanguage;

    Map<String, Map<String, String>> _localizedTexts = {
      'en': {
        'home': 'Home',
        'favorite': 'Notification',
        'tickets': 'Tracker ',
        'profile': 'Profile',
      },
      'ar': {
        'home': 'الرئيسية',
        'favorite': 'الإشعارات',
        'tickets': 'تتبع',
        'profile': 'الحساب',
      },
    };

    final texts = _localizedTexts[currentLanguage]!;

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Colors.white,
        selectedItemColor: const Color.fromARGB(255, 106, 31, 217),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: texts['home']!,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: texts['favorite']!,
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 106, 31, 217),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.medication, color: Colors.white),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: texts['tickets']!,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: texts['profile']!,
          ),
        ],
      ),
    );
  }
}
