import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class MedicineTrackingScreen extends StatefulWidget {
  const MedicineTrackingScreen({super.key});

  @override
  _MedicineTrackingScreenState createState() => _MedicineTrackingScreenState();
}

class _MedicineTrackingScreenState extends State<MedicineTrackingScreen> {
  DateTime currentWeek = DateTime.now();
  Future<Map<DateTime, DailyPerformance>>? _dailyPerformancesFuture;
  Map<DateTime, DailyPerformance> _dailyPerformances = {};
  late String _patientId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<DateTime, Timer> _dailyTimers = {};

  @override
  void initState() {
    super.initState();
    _loadPatientId().then((_) {
      _loadDailyPerformances();
    });
  }

  @override
  void dispose() {
    _dailyTimers.forEach((_, timer) {
      timer.cancel();
    });
    _dailyTimers.clear();
    super.dispose();
  }

  Future<void> _loadPatientId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _patientId = prefs.getString('patientId') ?? '';
  }

  Future<void> _loadDailyPerformances() async {
    setState(() {
      _dailyPerformancesFuture = _fetchDailyPerformances(currentWeek);
    });
    _dailyPerformances = await _dailyPerformancesFuture ?? {};
    setState(() {});
  }

  void _changeWeek(int days) {
    setState(() {
      currentWeek = currentWeek.add(Duration(days: days));
      _loadDailyPerformances();
    });
  }

  Future<Map<DateTime, DailyPerformance>> _fetchDailyPerformances(
      DateTime week) async {
    DateTime startOfWeek = week.subtract(Duration(days: week.weekday - 1));
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
    Map<DateTime, DailyPerformance> performances = {};

    if (_patientId.isEmpty) {
      print('No patientId found in SharedPreferences.');
      return {};
    }

    for (DateTime date = startOfWeek;
        date.isBefore(endOfWeek.add(const Duration(days: 1)));
        date = date.add(const Duration(days: 1))) {
      String dateString = DateFormat('yyyy-MM-dd').format(date);
      try {
        DocumentSnapshot performanceSnapshot = await _firestore
            .collection('ActivePatient')
            .doc(_patientId)
            .collection('DailyPerformances')
            .doc(dateString)
            .get();

        if (performanceSnapshot.exists) {
          Map<String, dynamic> performanceData =
              performanceSnapshot.data() as Map<String, dynamic>;
          performances[date] = DailyPerformance.fromJson(performanceData);
        } else {
          performances[date] = DailyPerformance(date: date);
        }
      } catch (e) {
        print('Error fetching daily performance for $dateString: $e');
        performances[date] = DailyPerformance(date: date);
      }
    }
    return performances;
  }

  PerformanceCategory _calculateDailyCategory(DailyPerformance performance) {
    if (performance.totalScheduled == 0) {
      return PerformanceCategory.none;
    }
    if (performance.dailyPercentage >= 80) {
      return PerformanceCategory.excellent;
    } else if (performance.dailyPercentage >= 60) {
      return PerformanceCategory.moderate;
    } else {
      return PerformanceCategory.poor;
    }
  }

  Color _getCategoryColor(PerformanceCategory category) {
    switch (category) {
      case PerformanceCategory.excellent:
        return Colors.green.shade400;
      case PerformanceCategory.moderate:
        return Colors.yellow.shade700;
      case PerformanceCategory.poor:
        return Colors.red.shade400;
      case PerformanceCategory.none:
      default:
        return Colors.grey.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocaleProvider>(context);
    String language = provider.currentLanguage;
    final bool isArabic = language == 'ar';

    Map<String, String> localizedTexts = {
      "en": "Your health is your priority. Stick to your medication schedule!",
      "ar": "صحتك أولويتك. التزم بجدول أدويتك!",
    };

    DateTime startOfWeek =
        currentWeek.subtract(Duration(days: currentWeek.weekday - 1));
    List<DateTime> weekDays =
        List.generate(7, (index) => startOfWeek.add(Duration(days: index)));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          language == 'en' ? 'Medicine Tracker' : 'متتبع الأدوية',
          style: const TextStyle(color: Colors.black, ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.lightBlue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lightbulb_outline, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localizedTexts[language]!,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const Divider(),
            _buildStatusIndicators(language, isArabic), 
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_left,
                      size: 30, color: Colors.grey),
                  onPressed: () => _changeWeek(-7),
                ),
                Flexible(
                  child: Text(
                    "${DateFormat('MMM dd', language == 'en' ? 'en_US' : 'ar_SA').format(weekDays.first)} - ${DateFormat('MMM dd', language == 'en' ? 'en_US' : 'ar_SA').format(weekDays.last)}, ${DateFormat('yyyy').format(weekDays.first)}",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_right,
                      size: 30, color: Colors.grey),
                  onPressed: () => _changeWeek(7),
                ),
              ],
            ),
            const SizedBox(height: 15),
            FutureBuilder<Map<DateTime, DailyPerformance>>(
              future: _dailyPerformancesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text('Error loading data: ${snapshot.error}');
                }
                final performances = snapshot.data ?? {};
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final double spacing = 8;
                  
                    final double itemWidth = (constraints.maxWidth - (6 * spacing)) / 7; 
                    
                    return Wrap(
                      spacing: spacing, 
                      runSpacing: spacing,
                      alignment: WrapAlignment.center,
                      children: weekDays.map((date) {
                        final performance = performances[date] ??
                            DailyPerformance(date: date);
                        final category = _calculateDailyCategory(performance);
                        final statusColor = _getCategoryColor(category);
                        return SizedBox(
                          width: itemWidth,
                          child: Column(
                            children: [
                              Text(
                                DateFormat('d', language == 'en' ? 'en_US' : 'ar_SA')
                                    .format(date),
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 16),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                width: 35,
                                height: 35,
                                decoration: BoxDecoration(
                                    color: statusColor,
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicators(String language, bool isArabic) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: isArabic ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                  children: [
                    _buildStatusIndicator(
                        language == 'en' ? "Excellent" : "ممتاز", Colors.green.shade400, isArabic),
                    const SizedBox(height: 10),
                    _buildStatusIndicator(
                        language == 'en' ? "Moderate" : "متوسط", Colors.yellow.shade700, isArabic),
                    const SizedBox(height: 10),
                    _buildStatusIndicator(
                        language == 'en' ? "Poor" : "ضعيف", Colors.red.shade400, isArabic),
                    const SizedBox(height: 10),
                    _buildStatusIndicator(language == 'en' ? "No Data" : "لا توجد بيانات",
                        Colors.grey.shade300, isArabic),
                  ],
                ),
              ),
              const SizedBox(width: 30),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Image.asset('assets/medicins.png', width: 180),
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              FittedBox(
                fit: BoxFit.contain,
                child: Image.asset('assets/medicins.png', width: 150),
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusIndicator(
                      language == 'en' ? "Excellent" : "ممتاز", Colors.green.shade400, isArabic),
                  const SizedBox(height: 10),
                  _buildStatusIndicator(
                      language == 'en' ? "Moderate" : "متوسط", Colors.yellow.shade700, isArabic),
                  const SizedBox(height: 10),
                  _buildStatusIndicator(
                      language == 'en' ? "Poor" : "ضعيف", Colors.red.shade400, isArabic),
                  const SizedBox(height: 10),
                  _buildStatusIndicator(language == 'en' ? "No Data" : "لا توجد بيانات",
                      Colors.grey.shade300, isArabic),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildStatusIndicator(String text, Color color, bool isArabic) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isArabic ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(5)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}


enum PerformanceCategory { excellent, moderate, poor, none }

class DailyPerformance {
  int totalScheduled = 0;
  int excellent = 0;

  int poor = 0;
  double dailyPercentage = 0.0;
  DateTime date;

  DailyPerformance({
    this.totalScheduled = 0,
    this.excellent = 0,
    this.poor = 0,
    this.dailyPercentage = 0.0,
    required this.date,
  });

  factory DailyPerformance.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['date'] is Timestamp) {
      parsedDate = (json['date'] as Timestamp).toDate();
    }
    else if (json['date'] is String) {
      parsedDate = DateTime.parse(json['date']);
    } else {
      print('Warning: Unexpected type for "date" field in DailyPerformance: ${json['date'].runtimeType}');
      parsedDate = DateTime.now();
    }

    return DailyPerformance(
      totalScheduled: json['totalScheduled'] ?? 0,
      excellent: json['excellent'] ?? 0,
      poor: json['poor'] ?? 0,
      dailyPercentage: (json['dailyPercentage'] as num?)?.toDouble() ?? 0.0,
      date: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalScheduled': totalScheduled,
      'excellent': excellent,
      'poor': poor,
      'dailyPercentage': dailyPercentage,
      'date': date.toIso8601String(),
    };
  }
}