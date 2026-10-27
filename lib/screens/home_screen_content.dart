import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:med_ad_app/main.dart'
    show calculateAndSaveDailyPerformance, refreshLocalReminders;
import 'package:med_ad_app/services/dose_service.dart';
import 'package:med_ad_app/services/local_reminders.dart';
import 'package:med_ad_app/theme/app_theme.dart';

/// Home: today's full schedule, the dose due now and today's progress.
class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({super.key});

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  String _patientId = '';
  String _firstName = '';
  TodaySchedule? _schedule;
  ProgressStats? _progress;
  bool _loading = true;
  String? _error;
  final Set<String> _saving = {};

  Timer? _ticker;
  StreamSubscription<QuerySnapshot>? _medsSub;
  StreamSubscription<QuerySnapshot>? _logsSub;

  @override
  void initState() {
    super.initState();
    _init();
    // refresh countdowns and statuses every minute
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _reload(silent: true));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _medsSub?.cancel();
    _logsSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _patientId = prefs.getString('patientId') ?? '';
    if (_patientId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    FirebaseFirestore.instance
        .collection('ActivePatient')
        .doc(_patientId)
        .get()
        .then((doc) {
      final full = '${doc.data()?['patientName'] ?? ''}'.trim();
      if (mounted && full.isNotEmpty) {
        setState(() => _firstName = full.split(' ').first);
      }
    }).catchError((_) {});

    _medsSub = FirebaseFirestore.instance
        .collection('ActivePatient')
        .doc(_patientId)
        .collection('PatientMedicine')
        .snapshots()
        .listen((_) {
      refreshLocalReminders(); // medicines changed -> new reminders
      _reload(silent: true);
    }, onError: (e) => debugPrint('medicines listener: $e'));

    _logsSub = FirebaseFirestore.instance
        .collectionGroup('MedicineIntakeLogs')
        .where('takenBy', isEqualTo: _patientId)
        .snapshots()
        .listen((_) => _reload(silent: true),
            onError: (e) => debugPrint('logs listener: $e'));

    await _reload();
  }

  Future<void> _reload({bool silent = false}) async {
    if (_patientId.isEmpty) return;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DoseService.loadToday(_patientId),
        DoseService.loadProgress(_patientId),
      ]);
      if (!mounted) return;
      setState(() {
        _schedule = results[0] as TodaySchedule;
        _progress = results[1] as ProgressStats;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _confirm(DoseItem dose) async {
    final key = '${dose.medicineId}_${dose.scheduled.millisecondsSinceEpoch}';
    setState(() => _saving.add(key));
    String msg;
    try {
      msg = await LocalReminders.recordTaken(
        patientId: _patientId,
        medicineId: dose.medicineId,
        scheduled: dose.scheduled,
        source: 'app',
      );
    } catch (e) {
      msg = tr(context, 'تعذّر حفظ الجرعة، يرجى المحاولة مرة أخرى.',
          'Could not save the dose. Please try again.', listen: false);
    }
    if (!mounted) return;
    setState(() => _saving.remove(key));
    final ok = msg.startsWith('تم');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? tr(context, 'تم تسجيل الجرعة، شكرًا لالتزامك.',
              'Dose recorded. Thank you!', listen: false)
          : msg),
    ));
    calculateAndSaveDailyPerformance();
    _reload(silent: true);
  }

  // ---------------------------------------------------------------- text

  String _time(DateTime t) {
    final ar = isArabic(context);
    final s = DateFormat('h:mm', 'en').format(t);
    final ampm = t.hour < 12 ? (ar ? 'ص' : 'AM') : (ar ? 'م' : 'PM');
    return '$s $ampm';
  }

  String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (!isArabic(context)) {
      final parts = [if (h > 0) '${h}h', if (m > 0) '${m}m'];
      return parts.isEmpty ? 'less than a minute' : parts.join(' ');
    }
    String hours;
    if (h == 0) {
      hours = '';
    } else if (h == 1) {
      hours = 'ساعة';
    } else if (h == 2) {
      hours = 'ساعتان';
    } else if (h <= 10) {
      hours = '$h ساعات';
    } else {
      hours = '$h ساعة';
    }
    String mins;
    if (m == 0) {
      mins = '';
    } else if (m == 1) {
      mins = 'دقيقة';
    } else if (m == 2) {
      mins = 'دقيقتان';
    } else if (m <= 10) {
      mins = '$m دقائق';
    } else {
      mins = '$m دقيقة';
    }
    final parts = [hours, mins].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? 'أقل من دقيقة' : parts.join(' و');
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = _schedule;
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _reload(silent: true),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(),
            Transform.translate(
              offset: const Offset(0, -44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _summaryCard(),
              ),
            ),
            if (_loading && s == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && s == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr(context, 'تعذّر تحميل البيانات. اسحب الشاشة للأسفل لإعادة المحاولة.',
                      'Could not load data. Pull down to try again.'),
                  textAlign: TextAlign.center,
                ),
              )
            else if (s != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (s.due.isNotEmpty) ...[
                      SectionTitle(tr(context, 'حان موعد الجرعة الآن', 'Due now')),
                      for (final d in s.due) ...[
                        _dueCard(d),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                    ],
                    SectionTitle(
                      tr(context, 'جدول اليوم', "Today's schedule"),
                      trailing: tr(context, '${s.today.length} جرعات',
                          '${s.today.length} doses'),
                    ),
                    if (s.today.isEmpty)
                      AppCard(
                        child: Text(
                          tr(context, 'لا توجد جرعات مجدولة اليوم.',
                              'No doses scheduled today.'),
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    else
                      AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < s.today.length; i++)
                              _timelineRow(s.today[i], last: i == s.today.length - 1),
                          ],
                        ),
                      ),
                    if (s.yesterdayMissed.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final d in s.yesterdayMissed) ...[
                        _missedYesterday(d),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final now = DateTime.now();
    final ar = isArabic(context);
    final date = DateFormat(ar ? 'EEEE، d MMMM' : 'EEEE, d MMMM', ar ? 'ar' : 'en')
        .format(now);
    final greeting = now.hour < 12
        ? tr(context, 'صباح الخير', 'Good morning')
        : tr(context, 'مساء الخير', 'Good evening');
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 20, 20, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date,
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
          const SizedBox(height: 2),
          Text(
            _firstName.isEmpty ? greeting : '$greeting، $_firstName',
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final s = _schedule;
    final total = s?.today.length ?? 0;
    final taken = s?.takenCount ?? 0;
    final remaining = s?.remainingCount ?? 0;
    final streak = _progress?.currentStreak ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0F2A3A).withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : taken / total,
                    strokeWidth: 8,
                    backgroundColor: AppColors.grey,
                    color: AppColors.primary,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$taken/$total',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(tr(context, 'جرعات', 'doses'),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'تقدّم اليوم', "Today's progress"),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (streak > 0)
                  Row(children: [
                    const Icon(Icons.local_fire_department_outlined,
                        size: 18, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tr(context, '$streak ${streak == 1 ? 'يوم' : streak == 2 ? 'يومان' : streak <= 10 ? 'أيام' : 'يومًا'} التزام متتالية',
                            '$streak-day streak'),
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ),
                  ]),
                const SizedBox(height: 4),
                Text(
                  total == 0
                      ? tr(context, 'لا توجد جرعات اليوم', 'No doses today')
                      : remaining == 0
                          ? tr(context, 'أحسنت، أكملت جرعات اليوم', 'Well done, all done for today')
                          : tr(context,
                              'تبقّت $remaining ${remaining == 1 ? 'جرعة' : remaining == 2 ? 'جرعتان' : 'جرعات'} اليوم – أنت على الطريق الصحيح',
                              '$remaining doses left today – keep going'),
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillImage(DoseItem d, {double size = 64}) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.medication_outlined,
          color: AppColors.primary, size: size * 0.5),
    );
    if (d.imageUrl == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        d.imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }

  Widget _dueCard(DoseItem d) {
    final key = '${d.medicineId}_${d.scheduled.millisecondsSinceEpoch}';
    final saving = _saving.contains(key);
    final left = d.timeLeft;
    final urgent = left.inMinutes <= 30;
    final details = [
      if (d.pills.isNotEmpty) tr(context, 'عدد الحبوب: ${d.pills}', 'Pills: ${d.pills}'),
      if (d.instructions.isNotEmpty && d.instructions != '__') d.instructions,
    ].join(' · ');
    return AppCard(
      borderColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _pillImage(d),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (d.dosage.isNotEmpty)
                      Text(tr(context, 'الجرعة: ${d.dosage}', 'Dose: ${d.dosage}'),
                          style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
                    if (details.isNotEmpty)
                      Text(details,
                          style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
                    Text(tr(context, 'الموعد ${_time(d.scheduled)}', 'At ${_time(d.scheduled)}'),
                        style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: urgent ? AppColors.dangerTint : AppColors.warningTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 18, color: urgent ? AppColors.danger : AppColors.warningText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(context, 'يتبقّى ${_duration(left)} لتسجيل الجرعة',
                        '${_duration(left)} left to record this dose'),
                    style: TextStyle(
                        color: urgent ? AppColors.danger : AppColors.warningText,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: saving ? null : () => _confirm(d),
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 24),
            label: Text(tr(context, 'أخذت الدواء', 'I took it')),
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(DoseItem d, {required bool last}) {
    late Color bg, fg;
    late IconData icon;
    late String status;
    switch (d.status) {
      case DoseStatus.taken:
        bg = AppColors.successTint;
        fg = AppColors.success;
        icon = Icons.check_rounded;
        status = d.takenAt == null
            ? tr(context, 'تم التسجيل', 'Recorded')
            : tr(context, 'تم التسجيل ${_time(d.takenAt!)}', 'Recorded ${_time(d.takenAt!)}');
        break;
      case DoseStatus.due:
        bg = AppColors.primary;
        fg = AppColors.primary;
        icon = Icons.schedule_rounded;
        status = tr(context, 'الآن · بانتظار التسجيل', 'Now · waiting');
        break;
      case DoseStatus.upcoming:
        bg = AppColors.grey;
        fg = AppColors.textMuted;
        icon = Icons.nightlight_outlined;
        final until = d.scheduled.difference(DateTime.now());
        status = tr(context, 'بعد ${_duration(until)} · سيصلك تذكير',
            'In ${_duration(until)} · you will be reminded');
        break;
      case DoseStatus.missed:
        bg = AppColors.dangerTint;
        fg = AppColors.danger;
        icon = Icons.close_rounded;
        status = tr(context, 'لم تُسجَّل الجرعة – انتهى وقت التسجيل',
            'Not recorded – time is over');
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(_time(d.scheduled),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: d.status == DoseStatus.due ? FontWeight.w700 : FontWeight.w600,
                    color: d.status == DoseStatus.due ? AppColors.primary : AppColors.textMuted)),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon,
                size: 18, color: d.status == DoseStatus.due ? Colors.white : fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(status,
                    style: TextStyle(
                        fontSize: 13,
                        color: fg,
                        fontWeight:
                            d.status == DoseStatus.due ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _missedYesterday(DoseItem d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5B4B4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: AppColors.dangerTint, shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'أمس ${_time(d.scheduled)} · ${d.name}',
                        'Yesterday ${_time(d.scheduled)} · ${d.name}'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(tr(context, 'لم تُسجَّل الجرعة – انتهى وقت التسجيل',
                        'Not recorded – time is over'),
                    style: const TextStyle(fontSize: 13, color: AppColors.danger)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
