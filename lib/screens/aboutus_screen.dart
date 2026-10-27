import 'package:flutter/material.dart';

import 'package:med_ad_app/theme/app_theme.dart';

/// "عن التطبيق".
class AboutusScreen extends StatelessWidget {
  const AboutusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final features = isArabic(context)
        ? const [
            'تذكير بمواعيد الأدوية مع زر لتسجيل الجرعة من الإشعار',
            'جدول كامل لجرعات اليوم وحالة كل جرعة',
            'قائمة شاملة بأدويتك وجرعاتها وتعليماتها',
            'متابعة التزامك اليومي والأسبوعي والشهري',
          ]
        : const [
            'Dose reminders with a button to record the dose',
            'A full schedule of today’s doses and their status',
            'All your medicines with doses and instructions',
            'Your daily, weekly and monthly adherence',
          ];
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'عن التطبيق', 'About the app'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                  color: AppColors.primaryTint, shape: BoxShape.circle),
              child: Image.asset('assets/2812649.png', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(tr(context, 'دوائي', 'Dawai'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          Center(
            child: Text(tr(context, 'صحتك في متناول يدك', 'Your health in your hands'),
                style: const TextStyle(color: AppColors.textMuted)),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Text(
              tr(context,
                  'دوائي تطبيق يساعدك على إدارة أدويتك ومواعيد تناولها بسهولة، ويذكّرك بكل جرعة في وقتها، ويتيح لك تسجيلها ومتابعة التزامك.',
                  'Dawai helps you manage your medicines and their times, reminds you of every dose, and lets you record it and follow your adherence.'),
              style: const TextStyle(fontSize: 15, height: 1.8),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'الميزات الرئيسية', 'Main features'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final f in features)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(f, style: const TextStyle(fontSize: 15, height: 1.6))),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
