import 'package:flutter/material.dart';

import 'package:med_ad_app/main.dart'
    show calculateAndSaveDailyPerformance, refreshLocalReminders;
import 'package:med_ad_app/screens/home_screen_content.dart';
import 'package:med_ad_app/screens/medication_screen.dart';
import 'package:med_ad_app/screens/notification_screen.dart';
import 'package:med_ad_app/screens/profile_screen.dart';
import 'package:med_ad_app/screens/tracker_screen.dart';
import 'package:med_ad_app/services/device_registration.dart';
import 'package:med_ad_app/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  // Pages keep their state when switching tabs.
  final List<Widget> _pages = const [
    HomeScreenContent(),
    MedicineTrackingScreen(),
    MyMedScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the patient comes back to the app: refresh token + "last opened".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DeviceRegistration.sync();
      calculateAndSaveDailyPerformance();
      refreshLocalReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home_rounded, tr(context, 'الرئيسية', 'Home')),
      (Icons.insights_outlined, Icons.insights_rounded, tr(context, 'تقدّمي', 'Progress')),
      (Icons.medication_outlined, Icons.medication_rounded, tr(context, 'أدويتي', 'Medicines')),
      (Icons.notifications_none_rounded, Icons.notifications_rounded,
          tr(context, 'الإشعارات', 'Alerts')),
      (Icons.person_outline_rounded, Icons.person_rounded, tr(context, 'حسابي', 'Account')),
    ];
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryTint,
        surfaceTintColor: Colors.white,
        height: 68,
        destinations: [
          for (final it in items)
            NavigationDestination(
              icon: Icon(it.$1, color: AppColors.textMuted),
              selectedIcon: Icon(it.$2, color: AppColors.primary),
              label: it.$3,
            ),
        ],
      ),
    );
  }
}
