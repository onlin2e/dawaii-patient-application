import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:med_ad_app/screens/splash_screen.dart';
import 'package:provider/provider.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocaleProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(provider.currentLanguage), 
      supportedLocales: const [
        Locale('en'), 
        Locale('ar'), 
      ],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate, // دعم الترجمة للواجهة
        GlobalWidgetsLocalizations.delegate,  // دعم الترجمة للأدوات
        GlobalCupertinoLocalizations.delegate, // دعم الترجمة في iOS
      ],
      home: const SplashScreen(),
    );
  }
}