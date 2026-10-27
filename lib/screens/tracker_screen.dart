import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:med_ad_app/services/dose_service.dart';
import 'package:med_ad_app/theme/app_theme.dart';

/// "تقدّمي": streak, this week, this month and badges.
class MedicineTrackingScreen extends StatefulWidget {
  const MedicineTrackingScreen({super.key});

  @override
  State<MedicineTrackingScreen> createState() => _MedicineTrackingScreenState();
}

class _MedicineTrackingScreenState extends State<MedicineTrackingScreen> {
  Future<ProgressStats?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ProgressStats?> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('patientId') ?? '';
    if (id.isEmpty) return null;
    return DoseService.loadProgress(id);
  }

  String _days(int n) {
    if (!isArabic(context)) return n == 1 ? '1 day' : '$n days';
    if (n == 1) return 'يوم واحد';
    if (n == 2) return 'يومان';
    if (n >= 3 && n <= 10) return '$n أيام';
    return '$n يومًا';
  }

  String _pct(double r) => '${(r * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            setState(() => _future = _load());
            await _future;
          },
          child: FutureBuilder<ProgressStats?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final p = snap.data;
              if (snap.hasError || p == null) {
                return ListView(children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(tr(context, 'تعذّر تحميل البيانات.', 'Could not load data.')),
                  ),
                ]);
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  Text(tr(context, 'تقدّمي', 'My progress'),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      tr(context, 'التزامك بالأدوية خلال الأسابيع الماضية',
                          'Your adherence over the past weeks'),
                      style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
                  const SizedBox(height: 16),
                  _streakCard(p),
                  const SizedBox(height: 16),
                  _weekCard(p),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _monthCard(p)),
                    const SizedBox(width: 12),
                    Expanded(child: _longestCard(p)),
                  ]),
                  const SizedBox(height: 16),
                  _badgesCard(p),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _streakCard(ProgressStats p) {
    final next = p.nextBadge;
    final String message;
    if (next == null) {
      message = tr(context, 'إنجاز رائع! حصلت على جميع الشارات.',
          'Amazing! You earned every badge.');
    } else if (p.currentStreak == 0) {
      message = tr(context, 'سجّل جميع جرعات اليوم لتبدأ سلسلة التزام جديدة.',
          'Record all of today’s doses to start a new streak.');
    } else {
      final left = next - p.currentStreak;
      message = tr(context, 'ممتاز! تبقّت ${_days(left)} للحصول على شارة «${_days(next)} التزام».',
          'Great! ${_days(left)} left to earn the “${_days(next)}” badge.');
    }
    final progress = next == null ? 1.0 : p.currentStreak / next;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_fire_department_outlined,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_days(p.currentStreak),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                Text(tr(context, 'التزام كامل متتالٍ', 'full adherence in a row'),
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15)),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          Text(message,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0).toDouble(),
              minHeight: 10,
              color: Colors.white,
              backgroundColor: Colors.white.withOpacity(0.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekCard(ProgressStats p) {
    final ar = isArabic(context);
    final today = DateTime.now();
    Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(tr(context, 'آخر 7 أيام', 'Last 7 days'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Text(_pct(p.weekRate),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.weekRate >= 0.75 ? AppColors.success : AppColors.warning)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in p.last7)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 22,
                          height: d.hasDoses ? (6 + 94 * d.rate) : 6,
                          decoration: BoxDecoration(
                            color: !d.hasDoses
                                ? AppColors.border
                                : d.complete
                                    ? AppColors.success
                                    : AppColors.warning,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateUtils.isSameDay(d.day, today)
                              ? tr(context, 'اليوم', 'Today')
                              : DateFormat('EEE', ar ? 'ar' : 'en').format(d.day),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: DateUtils.isSameDay(d.day, today)
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: DateUtils.isSameDay(d.day, today)
                                  ? AppColors.primary
                                  : AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 6, children: [
            legend(AppColors.success, tr(context, 'جميع الجرعات', 'All doses')),
            legend(AppColors.warning, tr(context, 'جرعة لم تُسجَّل', 'Missed a dose')),
            legend(AppColors.border, tr(context, 'لا توجد جرعات', 'No doses')),
          ]),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, String? hint, Color hintColor) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(fontSize: 12, color: hintColor)),
          ],
        ],
      ),
    );
  }

  Widget _monthCard(ProgressStats p) {
    String? hint;
    var color = AppColors.textMuted;
    final prev = p.previousMonthRate;
    if (prev != null) {
      final diff = ((p.monthRate - prev) * 100).round();
      if (diff > 0) {
        hint = tr(context, 'أفضل من الشهر الماضي بـ $diff%', '$diff% better than last month');
        color = AppColors.success;
      } else if (diff < 0) {
        hint = tr(context, 'أقل من الشهر الماضي بـ ${-diff}%', '${-diff}% lower than last month');
        color = AppColors.warning;
      } else {
        hint = tr(context, 'مثل الشهر الماضي', 'Same as last month');
      }
    }
    return _statCard(tr(context, 'التزام هذا الشهر', 'This month'), _pct(p.monthRate), hint, color);
  }

  Widget _longestCard(ProgressStats p) {
    return _statCard(tr(context, 'أطول سلسلة', 'Longest streak'), _days(p.longestStreak),
        tr(context, 'خلال آخر 70 يومًا', 'in the last 70 days'), AppColors.textMuted);
  }

  Widget _badgesCard(ProgressStats p) {
    final badges = <(String, bool, Widget)>[
      (
        tr(context, 'أول جرعة', 'First dose'),
        p.anyTaken,
        const Icon(Icons.check_rounded, size: 26),
      ),
      for (final n in [3, 7, 30])
        (
          n == 7
              ? tr(context, 'أسبوع كامل', 'Full week')
              : n == 30
                  ? tr(context, 'شهر كامل', 'Full month')
                  : _days(n),
          p.longestStreak >= n,
          Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'شاراتي', 'My badges'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final b in badges)
                Expanded(
                  child: Column(children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: b.$2 ? AppColors.primaryTint : AppColors.grey,
                        shape: BoxShape.circle,
                        border: b.$2
                            ? null
                            : Border.all(color: const Color(0xFFC9D3DA), width: 2),
                      ),
                      alignment: Alignment.center,
                      child: IconTheme(
                        data: IconThemeData(
                            color: b.$2 ? AppColors.primary : const Color(0xFF7C8A97)),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                              color: b.$2 ? AppColors.primary : const Color(0xFF7C8A97)),
                          child: b.$3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(b.$1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            color: b.$2 ? AppColors.text : AppColors.textMuted)),
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
