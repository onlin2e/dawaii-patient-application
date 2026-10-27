import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:med_ad_app/services/local_reminders.dart';

enum DoseStatus { taken, due, upcoming, missed }

class DoseItem {
  final String medicineId;
  final String name;
  final String dosage;
  final String pills;
  final String instructions;
  final String? imageUrl;
  final DateTime scheduled;
  final DoseStatus status;
  final DateTime? takenAt;

  const DoseItem({
    required this.medicineId,
    required this.name,
    required this.dosage,
    required this.pills,
    required this.instructions,
    required this.imageUrl,
    required this.scheduled,
    required this.status,
    required this.takenAt,
  });

  /// Time left to record the dose (3-hour rule).
  Duration get timeLeft =>
      scheduled.add(LocalReminders.recordWindow).difference(DateTime.now());
}

class TodaySchedule {
  final List<DoseItem> today;
  final List<DoseItem> yesterdayMissed;
  const TodaySchedule(this.today, this.yesterdayMissed);

  List<DoseItem> get due =>
      today.where((d) => d.status == DoseStatus.due).toList();
  int get takenCount => today.where((d) => d.status == DoseStatus.taken).length;
  int get remainingCount =>
      today.where((d) => d.status == DoseStatus.due || d.status == DoseStatus.upcoming).length;
}

class DayPerformance {
  final DateTime day;
  final int scheduled;
  final int taken;
  const DayPerformance(this.day, this.scheduled, this.taken);
  bool get hasDoses => scheduled > 0;
  bool get complete => scheduled > 0 && taken >= scheduled;
  double get rate => scheduled == 0 ? 0 : taken / scheduled;
}

class ProgressStats {
  final List<DayPerformance> last7; // oldest -> today
  final int currentStreak;
  final int longestStreak;
  final double monthRate;
  final double? previousMonthRate;
  final bool anyTaken;

  const ProgressStats({
    required this.last7,
    required this.currentStreak,
    required this.longestStreak,
    required this.monthRate,
    required this.previousMonthRate,
    required this.anyTaken,
  });

  double get weekRate {
    final s = last7.fold<int>(0, (a, d) => a + d.scheduled);
    final t = last7.fold<int>(0, (a, d) => a + d.taken);
    return s == 0 ? 0 : t / s;
  }

  static const badgeDays = [3, 7, 10, 14, 30];

  int? get nextBadge {
    for (final b in badgeDays) {
      if (currentStreak < b) return b;
    }
    return null;
  }
}

/// Reads medicines and intake logs and builds what the screens show.
class DoseService {
  static final _db = FirebaseFirestore.instance;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Local "HH:mm" times of a medicine (nowTime; MedicineTime is UTC).
  static List<List<int>> _times(Map<String, dynamic> d) {
    final out = <List<int>>[];
    final local = d['nowTime'];
    if (local is List && local.isNotEmpty) {
      for (final t in local) {
        final p = t.toString().split(':');
        final h = p.isNotEmpty ? int.tryParse(p[0]) : null;
        final m = p.length > 1 ? int.tryParse(p[1]) : null;
        if (h != null && m != null) out.add([h, m]);
      }
      return out;
    }
    final utc = d['MedicineTime'];
    if (utc is List) {
      final now = DateTime.now();
      for (final t in utc) {
        final p = t.toString().split(':');
        final h = p.isNotEmpty ? int.tryParse(p[0]) : null;
        final m = p.length > 1 ? int.tryParse(p[1]) : null;
        if (h == null || m == null) continue;
        final l = DateTime.utc(now.year, now.month, now.day, h, m).toLocal();
        out.add([l.hour, l.minute]);
      }
    }
    return out;
  }

  static Future<TodaySchedule> loadToday(String patientId) async {
    final now = DateTime.now();
    final today = _day(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final patientRef = _db.collection('ActivePatient').doc(patientId);
    final meds = await patientRef.collection('PatientMedicine').get();

    final todayList = <DoseItem>[];
    final missedYesterday = <DoseItem>[];

    await Future.wait(meds.docs.map((med) async {
      final d = med.data();
      final start = d['StartDate'];
      final end = d['EndDate'];
      if (start is! Timestamp || end is! Timestamp) return;
      final startDay = _day(start.toDate());
      final endDay = _day(end.toDate());
      final times = _times(d);
      if (times.isEmpty) return;
      final activeToday = !today.isBefore(startDay) && !today.isAfter(endDay);
      final activeYesterday =
          !yesterday.isBefore(startDay) && !yesterday.isAfter(endDay);
      if (!activeToday && !activeYesterday) return;

      final logs = await patientRef
          .collection('PatientMedicine')
          .doc(med.id)
          .collection('MedicineIntakeLogs')
          .where('scheduledTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday))
          .get();
      final taken = <String, DateTime?>{};
      for (final l in logs.docs) {
        final data = l.data();
        if (data['taken'] == true) {
          final ta = data['takenAt'];
          taken[l.id] = ta is Timestamp ? ta.toDate() : null;
        }
      }

      DoseItem build(DateTime at) {
        final id = '${med.id}_${at.millisecondsSinceEpoch}';
        DoseStatus status;
        if (taken.containsKey(id)) {
          status = DoseStatus.taken;
        } else if (now.isBefore(at.subtract(const Duration(minutes: 1)))) {
          status = DoseStatus.upcoming;
        } else if (now.isBefore(at.add(LocalReminders.recordWindow))) {
          status = DoseStatus.due;
        } else {
          status = DoseStatus.missed;
        }
        final img = d['MedicineImageUrl'];
        return DoseItem(
          medicineId: med.id,
          name: '${d['MedicineName'] ?? ''}',
          dosage: '${d['MedicineDosage'] ?? ''}',
          pills: '${d['NumberOfPillsPerDose'] ?? ''}',
          instructions: '${d['Medication Instructions'] ?? ''}',
          imageUrl: img is String && img.isNotEmpty ? img : null,
          scheduled: at,
          status: status,
          takenAt: taken[id],
        );
      }

      for (final t in times) {
        if (activeToday) {
          todayList.add(build(DateTime(today.year, today.month, today.day, t[0], t[1])));
        }
        if (activeYesterday) {
          final y = build(
              DateTime(yesterday.year, yesterday.month, yesterday.day, t[0], t[1]));
          if (y.status == DoseStatus.missed) missedYesterday.add(y);
        }
      }
    }));

    todayList.sort((a, b) => a.scheduled.compareTo(b.scheduled));
    missedYesterday.sort((a, b) => a.scheduled.compareTo(b.scheduled));
    return TodaySchedule(todayList, missedYesterday);
  }

  /// Progress from DailyPerformances (kept up to date by the app).
  static Future<ProgressStats> loadProgress(String patientId) async {
    final now = DateTime.now();
    final today = _day(now);
    final from = today.subtract(const Duration(days: 69));
    final fmt = DateFormat('yyyy-MM-dd');

    final snap = await _db
        .collection('ActivePatient')
        .doc(patientId)
        .collection('DailyPerformances')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: fmt.format(from))
        .get();

    final byDay = <String, DayPerformance>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      final day = DateTime.tryParse(doc.id);
      if (day == null) continue;
      byDay[doc.id] = DayPerformance(
        day,
        (d['totalScheduled'] as num?)?.toInt() ?? 0,
        (d['excellent'] as num?)?.toInt() ?? 0,
      );
    }
    DayPerformance at(DateTime day) =>
        byDay[fmt.format(day)] ?? DayPerformance(day, 0, 0);

    // current streak: today counts only once complete, never breaks it
    var current = 0;
    for (var i = 0; i < 70; i++) {
      final p = at(today.subtract(Duration(days: i)));
      if (!p.hasDoses) continue;
      if (p.complete) {
        current++;
      } else if (i == 0) {
        continue;
      } else {
        break;
      }
    }

    var longest = 0, run = 0;
    for (var i = 69; i >= 0; i--) {
      final p = at(today.subtract(Duration(days: i)));
      if (!p.hasDoses) continue;
      if (p.complete) {
        run++;
        if (run > longest) longest = run;
      } else if (i != 0) {
        run = 0;
      }
    }

    double? rateOf(int year, int month) {
      var s = 0, t = 0;
      for (final p in byDay.values) {
        if (p.day.year == year && p.day.month == month) {
          s += p.scheduled;
          t += p.taken;
        }
      }
      return s == 0 ? null : t / s;
    }

    final prev = DateTime(today.year, today.month - 1, 1);
    return ProgressStats(
      last7: List.generate(7, (i) => at(today.subtract(Duration(days: 6 - i)))),
      currentStreak: current,
      longestStreak: longest,
      monthRate: rateOf(today.year, today.month) ?? 0,
      previousMonthRate: rateOf(prev.year, prev.month),
      anyTaken: byDay.values.any((p) => p.taken > 0),
    );
  }
}
