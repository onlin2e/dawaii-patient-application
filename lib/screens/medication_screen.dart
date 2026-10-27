import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:med_ad_app/theme/app_theme.dart';

/// "أدويتي": the patient's medicines.
class MyMedScreen extends StatefulWidget {
  const MyMedScreen({super.key});

  @override
  State<MyMedScreen> createState() => _MyMedScreenState();
}

class _MyMedScreenState extends State<MyMedScreen> {
  String? _patientId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _patientId = p.getString('patientId') ?? '');
    });
  }

  /// Local times: nowTime, or MedicineTime (UTC) converted.
  List<String> _times(Map<String, dynamic> d) {
    final local = d['nowTime'];
    if (local is List && local.isNotEmpty) {
      return local.map((e) => e.toString()).toList();
    }
    final utc = d['MedicineTime'];
    if (utc is! List) return const [];
    final now = DateTime.now();
    return utc.map((t) {
      final p = t.toString().split(':');
      final h = int.tryParse(p.first) ?? 0;
      final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
      final l = DateTime.utc(now.year, now.month, now.day, h, m).toLocal();
      return DateFormat('HH:mm').format(l);
    }).toList();
  }

  String _ampm(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? p[1].padLeft(2, '0') : '00';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final suffix = h < 12 ? tr(context, 'ص', 'AM') : tr(context, 'م', 'PM');
    return '$h12:$m $suffix';
  }

  bool _isActive(Map<String, dynamic> d) {
    final end = d['EndDate'];
    if (end is! Timestamp) return true;
    final e = end.toDate();
    final now = DateTime.now();
    return !DateTime(e.year, e.month, e.day).isBefore(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'أدويتي', 'My medicines'))),
      body: _patientId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('ActivePatient')
                  .doc(_patientId)
                  .collection('PatientMedicine')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                      child: Text(tr(context, 'تعذّر تحميل الأدوية.', 'Could not load medicines.')));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) {
                    final aa = _isActive(a.data()) ? 0 : 1;
                    final bb = _isActive(b.data()) ? 0 : 1;
                    return aa.compareTo(bb);
                  });
                if (docs.isEmpty) {
                  return Center(
                      child: Text(tr(context, 'لا توجد أدوية مسجّلة.', 'No medicines yet.'),
                          style: const TextStyle(color: AppColors.textMuted)));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _medicineCard(docs[i].data()),
                );
              },
            ),
    );
  }

  Widget _medicineCard(Map<String, dynamic> d) {
    final active = _isActive(d);
    final img = d['MedicineImageUrl'];
    final start = d['StartDate'];
    final end = d['EndDate'];
    final dateFmt = DateFormat('d MMM yyyy', isArabic(context) ? 'ar' : 'en');
    final instructions = '${d['Medication Instructions'] ?? ''}';
    final placeholder = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
          color: AppColors.primaryTint, borderRadius: BorderRadius.circular(16)),
      child: const Icon(Icons.medication_outlined, color: AppColors.primary, size: 32),
    );

    Widget info(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('$label: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ]),
        );

    return Opacity(
      opacity: active ? 1 : 0.6,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              img is String && img.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(img,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => placeholder),
                    )
                  : placeholder,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d['MedicineName'] ?? ''}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: active ? AppColors.successTint : AppColors.grey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        active
                            ? tr(context, 'دواء حالي', 'Current')
                            : tr(context, 'انتهت مدة الدواء', 'Finished'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active ? AppColors.success : AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 6),
            info(Icons.schedule_rounded, tr(context, 'المواعيد', 'Times'),
                _times(d).map(_ampm).join('، ')),
            if ('${d['MedicineDosage'] ?? ''}'.isNotEmpty)
              info(Icons.science_outlined, tr(context, 'الجرعة', 'Dose'), '${d['MedicineDosage']}'),
            if ('${d['NumberOfPillsPerDose'] ?? ''}'.isNotEmpty)
              info(Icons.medication_liquid_outlined, tr(context, 'عدد الحبوب', 'Pills'),
                  '${d['NumberOfPillsPerDose']}'),
            if (instructions.isNotEmpty && instructions != '__')
              info(Icons.info_outline, tr(context, 'التعليمات', 'Instructions'), instructions),
            if (start is Timestamp && end is Timestamp)
              info(Icons.date_range_outlined, tr(context, 'المدة', 'Period'),
                  '${dateFmt.format(start.toDate())} – ${dateFmt.format(end.toDate())}'),
          ],
        ),
      ),
    );
  }
}
