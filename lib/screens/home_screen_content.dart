
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({super.key});

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  String patientName = '...';
  bool _isConfirming = false;

  // نحتفظ بخريطة لتعطيل remind later محليًا (محفوظة إن احتجت لاحقًا)
  final Map<String, bool> _remindLaterButtonDisabled = {};

  // تهيئة المتغيرات كقيمة افتراضية لتفادي LateInitializationError
  late Future<List<Map<String, dynamic>>> _medicinesFuture = Future.value(<Map<String, dynamic>>[]);
  late Future<List<Map<String, dynamic>>> _takenTodayFuture = Future.value(<Map<String, dynamic>>[]);
  late Future<Map<String, int>> _todayTotalsFuture = Future.value({'totalScheduled': 0, 'takenCount': 0});

  // Subscriptions للـ realtime updates (hot reload)
  StreamSubscription<QuerySnapshot>? _patientMedicineSub;
  StreamSubscription<QuerySnapshot>? _intakeLogsSub;

  @override
  void initState() {
    super.initState();
    fetchPatientName();
    // تهيئة القيم عبر جلب البيانات الحقيقية
    _medicinesFuture = fetchScheduledMedicines();
    _refreshTakenAndTotals();
    _registerRealtimeListeners();
  }

  @override
  void dispose() {
    _patientMedicineSub?.cancel();
    _intakeLogsSub?.cancel();
    super.dispose();
  }

  // ============================
  // Realtime listeners to hot-reload UI when data changes
  // ============================
  Future<void> _registerRealtimeListeners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getString('patientId') ?? '';
      if (patientId.isEmpty) return;

      // Listener on PatientMedicine collection
      _patientMedicineSub = FirebaseFirestore.instance
          .collection('ActivePatient')
          .doc(patientId)
          .collection('PatientMedicine')
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        setState(() {
          _medicinesFuture = fetchScheduledMedicines();
          _refreshTakenAndTotals();
        });
      }, onError: (e) {
        print('PatientMedicine listener error: $e');
      });

      // Listener on MedicineIntakeLogs collectionGroup for this patient (takenBy == patientId)
      _intakeLogsSub = FirebaseFirestore.instance
          .collectionGroup('MedicineIntakeLogs')
          .where('takenBy', isEqualTo: patientId)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        setState(() {
          _medicinesFuture = fetchScheduledMedicines();
          _refreshTakenAndTotals();
        });
      }, onError: (e) {
        print('MedicineIntakeLogs listener error: $e');
      });
    } catch (e) {
      print('Failed to register realtime listeners: $e');
    }
  }

  void _refreshTakenAndTotals() {
    _takenTodayFuture = fetchTodayTakenMedicines();
    _todayTotalsFuture = computeTodayTotals();
  }

  // ============================
  // Helpers: patientId, token
  // ============================
  Future<String> getPatientId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('patientId') ?? '';
  }

  Future<String?> getDeviceToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      print("Error getting Firebase device token: $e");
      return null;
    }
  }

  Future<void> fetchPatientName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getString('patientId') ?? '';
      if (patientId.isEmpty) {
        setState(() => patientName = 'غير معروف');
        return;
      }

      final snapshot = await FirebaseFirestore.instance.collection('ActivePatient').doc(patientId).get();

      if (snapshot.exists) {
        final data = snapshot.data();
        final fullName = data?['patientName'] as String?;
        if (fullName != null && fullName.isNotEmpty) {
          setState(() => patientName = fullName.split(' ').first);
        } else {
          setState(() => patientName = 'غير معروف');
        }
      } else {
        setState(() => patientName = 'غير موجود');
      }
    } catch (e) {
      setState(() => patientName = 'خطأ في التحميل');
      print('Error fetching patient name: $e');
    }
  }

  // ============================
  // fetchScheduledMedicines
  // ============================
  Future<List<Map<String, dynamic>>> fetchScheduledMedicines() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String patientId = prefs.getString('patientId') ?? '';
    DateTime now = DateTime.now();

    List<Map<String, dynamic>> scheduledMedicines = [];

    if (patientId.isEmpty) return scheduledMedicines;

    final QuerySnapshot patientMedicineSnapshot = await FirebaseFirestore.instance
        .collection('ActivePatient')
        .doc(patientId)
        .collection('PatientMedicine')
        .get();

    for (var medicineDoc in patientMedicineSnapshot.docs) {
      final medicineData = medicineDoc.data() as Map<String, dynamic>;

      if (medicineData['StartDate'] == null ||
          medicineData['EndDate'] == null ||
          (medicineData['nowTime'] == null && medicineData['MedicineTime'] == null)) {
        continue;
      }

      final List<dynamic> nowTimes = medicineData['nowTime'] ?? medicineData['MedicineTime'] ?? [];

      DateTime startDate = ((medicineData['StartDate'] as Timestamp?)?.toDate()) ?? DateTime.now();
      DateTime endDate = ((medicineData['EndDate'] as Timestamp?)?.toDate()) ?? DateTime.now();

      if (now.isAfter(startDate.subtract(const Duration(days: 1))) &&
          now.isBefore(endDate.add(const Duration(days: 1)))) {
        for (var timeNow in nowTimes) {
          try {
            final parsedTime = DateFormat("HH:mm").parse(timeNow);
            final medicineDateTime = DateTime(now.year, now.month, now.day, parsedTime.hour, parsedTime.minute);

            final endTime = medicineDateTime.add(const Duration(hours: 3));
            final intakeLogDocId = '${medicineDoc.id}_${medicineDateTime.millisecondsSinceEpoch}';

            final intakeLogsRef = FirebaseFirestore.instance
                .collection('ActivePatient')
                .doc(patientId)
                .collection('PatientMedicine')
                .doc(medicineDoc.id)
                .collection('MedicineIntakeLogs')
                .doc(intakeLogDocId);

            final intakeLogSnapshot = await intakeLogsRef.get();
            final intakeLogData = intakeLogSnapshot.data() as Map<String, dynamic>?;

            if (now.isAfter(medicineDateTime.subtract(const Duration(minutes: 1))) &&
                now.isBefore(endTime)) {
              if (!intakeLogSnapshot.exists || !(intakeLogData?['taken'] == true)) {
                scheduledMedicines.add(Map<String, dynamic>.from(medicineData)
                  ..['scheduledTime'] = medicineDateTime
                  ..['medicineId'] = medicineDoc.id
                  ..['intakeLogDocId'] = intakeLogDocId);
              }
            }
          } catch (e) {
            print('Error parsing time: $timeNow - $e');
            continue;
          }
        }
      }
    }

    scheduledMedicines.sort((a, b) => (a['scheduledTime'] as DateTime).compareTo(b['scheduledTime'] as DateTime));
    return scheduledMedicines;
  }

  // ============================
  // Confirm action from UI
  // ============================
  Future<void> _confirmFromUI(Map<String, dynamic> med, String intakeLogDocId) async {
    setState(() => _isConfirming = true);

    final medicineId = med['medicineId'];
    final scheduledTime = med['scheduledTime'] as DateTime;

    if (medicineId != null && intakeLogDocId.isNotEmpty) {
      final now = DateTime.now();
      final patientId = await getPatientId();

      if (patientId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ: معرف المريض غير موجود')));
        setState(() => _isConfirming = false);
        return;
      }

      final intakeLogsRef = FirebaseFirestore.instance
          .collection('ActivePatient')
          .doc(patientId)
          .collection('PatientMedicine')
          .doc(medicineId)
          .collection('MedicineIntakeLogs')
          .doc(intakeLogDocId);

      await intakeLogsRef.set({
        'scheduledTime': Timestamp.fromDate(scheduledTime),
        'takenAt': Timestamp.fromDate(now),
        'takenBy': patientId,
        'taken': true,
        'missedReason': FieldValue.delete(),
      }, SetOptions(merge: true));

      setState(() {
        _medicinesFuture = fetchScheduledMedicines();
        _refreshTakenAndTotals();
      });

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تم التأكيد'),
          content: const Text('شكراً — تم تسجيل أخذ دوائك.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('حسناً')),
          ],
        ),
      );
    } else {
      print('خطأ: معرف الدواء أو معرف السجل غير صالح.');
    }

    setState(() => _isConfirming = false);
  }

  // ============================
  // Taken today and totals
  // ============================
  Future<List<Map<String, dynamic>>> fetchTodayTakenMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString('patientId') ?? '';
    if (patientId.isEmpty) return [];

    final List<Map<String, dynamic>> taken = [];
    final firestore = FirebaseFirestore.instance;

    final patientMedicineSnapshot = await firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('PatientMedicine')
        .get();

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    for (final medDoc in patientMedicineSnapshot.docs) {
      final medId = medDoc.id;
      final medData = medDoc.data() as Map<String, dynamic>? ?? {};

      final logsSnapshot = await firestore
          .collection('ActivePatient')
          .doc(patientId)
          .collection('PatientMedicine')
          .doc(medId)
          .collection('MedicineIntakeLogs')
          .where('taken', isEqualTo: true)
          .get();

      for (final logDoc in logsSnapshot.docs) {
        final log = logDoc.data();
        DateTime? takenAt;
        if (log['takenAt'] is Timestamp) {
          takenAt = (log['takenAt'] as Timestamp).toDate();
        } else if (log['takenAt'] is String) {
          takenAt = DateTime.tryParse(log['takenAt']);
        }
        DateTime? scheduledTime;
        if (log['scheduledTime'] is Timestamp) {
          scheduledTime = (log['scheduledTime'] as Timestamp).toDate();
        } else if (log['scheduledTime'] is String) {
          scheduledTime = DateTime.tryParse(log['scheduledTime']);
        }

        final checkTime = takenAt ?? scheduledTime;
        if (checkTime != null && !checkTime.isBefore(startOfDay) && checkTime.isBefore(endOfDay)) {
          taken.add({
            'medicineId': medId,
            'medicineName': medData['MedicineName'] ?? 'دواء',
            'takenAt': takenAt,
            'scheduledTime': scheduledTime,
            'intakeLogDocId': logDoc.id,
          });
        }
      }
    }

    taken.sort((a, b) {
      final da = a['takenAt'] as DateTime? ?? a['scheduledTime'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b['takenAt'] as DateTime? ?? b['scheduledTime'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });

    return taken;
  }

  Future<Map<String, int>> computeTodayTotals() async {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString('patientId') ?? '';
    if (patientId.isEmpty) return {'totalScheduled': 0, 'takenCount': 0};

    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    int totalScheduled = 0;

    final patientMedicineSnapshot = await firestore
        .collection('ActivePatient')
        .doc(patientId)
        .collection('PatientMedicine')
        .get();

    for (final medDoc in patientMedicineSnapshot.docs) {
      final medData = medDoc.data() as Map<String, dynamic>? ?? {};
      final List<dynamic>? times = medData['MedicineTime'] ?? medData['nowTime'];
      final Timestamp? startTs = medData['StartDate'];
      final Timestamp? endTs = medData['EndDate'];
      if (times == null || startTs == null || endTs == null) continue;

      final DateTime startDate = (startTs as Timestamp).toDate();
      final DateTime endDate = (endTs as Timestamp).toDate();
      final DateTime startDay = DateTime(startDate.year, startDate.month, startDate.day);
      final DateTime endDay = DateTime(endDate.year, endDate.month, endDate.day);

      if (!todayStart.isBefore(startDay) && !todayStart.isAfter(endDay) ||
          (!todayStart.isBefore(startDay) && !todayStart.isAfter(endDay))) {
        totalScheduled += times.length;
      } else {
        if (!todayStart.isBefore(startDay) && !todayStart.isAfter(endDay)) {
          totalScheduled += times.length;
        }
      }
    }

    final takenList = await fetchTodayTakenMedicines();
    final takenCount = takenList.length;

    return {'totalScheduled': totalScheduled, 'takenCount': takenCount};
  }

  // ============================
  // UI build
  // ============================
  @override
  Widget build(BuildContext context) {
    final currentLanguage = Provider.of<LocaleProvider>(context).currentLanguage;
    final texts = {
      'en': {
        'welcome': 'Welcome',
        'to_take': 'Medicines for Today',
        'confirm': 'Confirm',
        'today_progress': "Today's Progress",
        'no_meds': 'No medicines currently',
        'no_taken': 'No doses taken today yet',
      },
      'ar': {
        'welcome': 'أهلاً وسهلاً',
        'to_take': 'الأدوية الخاصة بك لهذا اليوم',
        'confirm': 'تأكيد',
        'today_progress': 'تقدّم اليوم',
        'no_meds': 'لا توجد أدوية حالياً',
        'no_taken': 'لم يتم أخذ أي جرعات اليوم بعد',
      },
    }[currentLanguage]!;

    final currentDate = DateTime.now();
    final dates = List.generate(5, (index) => currentDate.add(Duration(days: index - 2)));

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(texts['welcome']!, style: TextStyle(fontSize: screenHeight * 0.02, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(patientName, style: TextStyle(fontSize: screenHeight * 0.018, color: Colors.grey)),
              ]),
            ]),
          ),

          // Month Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${DateFormat.MMMM(currentLanguage == 'ar' ? 'ar' : 'en').format(currentDate)} ${currentDate.year}',
                  style: TextStyle(fontSize: screenHeight * 0.02, fontWeight: FontWeight.bold, color: const Color(0xFF6A1BE9))),
            ),
          ),

          const SizedBox(height: 12),

          // Dates strip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: dates.map((date) {
              final isToday = date.day == currentDate.day;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    decoration: isToday
                        ? BoxDecoration(color: const Color(0xFF6A1BE9), borderRadius: BorderRadius.circular(10))
                        : null,
                    child: Column(children: [
                      Text('${date.day}', style: TextStyle(color: isToday ? Colors.white : const Color(0xFF6A1BE9), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(DateFormat('EEE', currentLanguage == 'ar' ? 'ar' : 'en').format(date), style: TextStyle(color: isToday ? Colors.white : const Color(0xFF6A1BE9))),
                    ]),
                  )
                ]),
              );
            }).toList()),
          ),

          const SizedBox(height: 12),

          // Purple area
          Expanded(
            child: Container(
              width: screenWidth,
              decoration: const BoxDecoration(color: Color(0xFF6A1BE9), borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.all(16.0), child: Text(texts['to_take']!, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: screenHeight * 0.02))),

                // Scheduled meds list
                Expanded(
                  flex: 2,
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _medicinesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
                      if (snapshot.hasError) return Center(child: Text('خطأ أثناء جلب الأدوية', style: TextStyle(color: Colors.white)));
                      final meds = snapshot.data ?? [];
                      if (meds.isEmpty) return Center(child: Text(texts['no_meds']!, style: const TextStyle(color: Colors.white)));

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: meds.length,
                        itemBuilder: (context, index) {
                          final med = meds[index];
                          final name = med['MedicineName'] ?? 'اسم الدواء غير معروف';
                          final scheduledTime = med['scheduledTime'] as DateTime;
                          final dosage = med['MedicineDosage'] ?? 'غير محدد';
                          final condition = med['Medication Instructions'] ?? 'غير محدد';
                          final pillsPerDose = med['NumberOfPillsPerDose']?.toString() ?? 'غير محدد';
                          final timeFormat = DateFormat('h:mm a', 'en_US').format(scheduledTime);
                          final displayTime = timeFormat.replaceAll('AM', 'صباحاً').replaceAll('PM', 'مساءً');

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              color: Colors.white.withOpacity(0.95),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(name, style: const TextStyle(color: Color(0xFF6A1BE9), fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text('الوقت: $displayTime', style: const TextStyle(color: Colors.black87)),
                                  const SizedBox(height: 6),
                                  Text('الجرعة: $dosage', style: const TextStyle(color: Colors.black87)),
                                  Text('عدد الحبوب: $pillsPerDose', style: const TextStyle(color: Colors.black87)),
                                  Text('تعليمات: $condition', style: const TextStyle(color: Colors.black87)),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _isConfirming
                                            ? null
                                            : () async {
                                                setState(() => _isConfirming = true);
                                                final intakeLogDocId = med['intakeLogDocId'] as String;
                                                await _confirmFromUI(med, intakeLogDocId);
                                                setState(() => _isConfirming = false);
                                              },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green.shade600,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                        child: Text(texts['confirm']!),
                                      ),
                                    ),
                                  ]),
                                ]),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Today's progress header + totals
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(texts['today_progress']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    FutureBuilder<Map<String, int>>(
                      future: _todayTotalsFuture,
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        final totals = snap.data!;
                        final total = totals['totalScheduled'] ?? 0;
                        final taken = totals['takenCount'] ?? 0;
                        final percent = total > 0 ? ((taken / total) * 100).round() : 0;
                        return Text('$taken / $total  •  $percent%', style: const TextStyle(color: Colors.white));
                      },
                    ),
                  ]),
                ),

                // Taken list (white card area)
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _takenTodayFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          if (snapshot.hasError) return const Center(child: Text('خطأ أثناء جلب بيانات التقدّم'));
                          final taken = snapshot.data ?? [];
                          if (taken.isEmpty) return Center(child: Text(texts['no_taken']!, style: TextStyle(color: Colors.grey.shade700)));

                          return ListView.separated(
                            itemCount: taken.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, idx) {
                              final item = taken[idx];
                              final medName = item['medicineName'] ?? 'دواء';
                              final takenAt = item['takenAt'] as DateTime?;
                              final scheduledTime = item['scheduledTime'] as DateTime?;
                              final displayTime = (takenAt ?? scheduledTime)?.toLocal();
                              final timeStr = displayTime != null ? DateFormat('h:mm a').format(displayTime).replaceAll('AM', 'صباحاً').replaceAll('PM', 'مساءً') : '';

                              return ListTile(
                                leading: CircleAvatar(backgroundColor: Colors.green.shade400, child: const Icon(Icons.check, color: Colors.white)),
                                title: Text(medName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (timeStr.isNotEmpty) Text('الوقت: $timeStr'),
                                  const SizedBox(height: 4),
                                  const Text('عمل ممتاز! شكرًا لالتزامك.'),
                                ]),
                                trailing: IconButton(
                                  icon: const Icon(Icons.info_outline, color: Colors.grey),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (ctx) {
                                        return Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(medName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 8),
                                            if (timeStr.isNotEmpty) Text('تم أخذه عند: $timeStr'),
                                            const SizedBox(height: 8),
                                            const Text('تم تسجيل أخذ الدواء في السجل. شكرًا لك!'),
                                            const SizedBox(height: 12),
                                            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('حسناً')),
                                          ]),
                                        );
                                      },
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}