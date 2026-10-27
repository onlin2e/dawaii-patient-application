import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:med_ad_app/screens/splash_screen.dart';
import 'package:provider/provider.dart';
import 'package:med_ad_app/main.dart' show appMessengerKey;
import 'package:med_ad_app/theme/app_theme.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocaleProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      title: 'دوائي',
      theme: AppTheme.light(),
      locale: Locale(provider.currentLanguage), 
      supportedLocales: const [
        Locale('en'), 
        Locale('ar'), 
      ],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, 
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}