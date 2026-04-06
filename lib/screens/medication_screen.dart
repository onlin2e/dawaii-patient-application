import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:med_ad_app/provider/local_provider.dart';

class MyMedScreen extends StatefulWidget {
  const MyMedScreen({super.key});

  @override
  State<MyMedScreen> createState() => _MyMedScreenState();
}

class _MyMedScreenState extends State<MyMedScreen> {
  late String patientId;
  bool patientIdInitialized = false;

  @override
  void initState() {
    super.initState();
    _getPatientId();
  }

  Future<void> _getPatientId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    patientId = prefs.getString('patientId') ?? '';
    print('Patient ID: $patientId');
    setState(() {
      patientIdInitialized = true;
    });
  }

  String convertUtcToOmanTime(String timeUtc) {
    final utcTime = DateFormat("HH:mm").parseUtc(timeUtc);
    final omanTime = utcTime.add(const Duration(hours: 4));
    return DateFormat("HH:mm").format(omanTime);
  }

  @override
  Widget build(BuildContext context) {
    final currentLanguage = Provider.of<LocaleProvider>(context).currentLanguage;

    Map<String, Map<String, String>> _localizedTexts = {
      'en': {
        'title': 'My Medications',
        'no_medications': 'No medications available.',
        'dosage': 'Dosage:',
        'pills_per_dose': 'Pills per dose:',
        'medicine_times': 'Medicine times:',
        'start_date': 'Start date:',
        'end_date': 'End date:',
        'condition': 'Medication Instructions:',
      },
      'ar': {
        'title': 'أدويتي',
        'no_medications': 'لا توجد أدوية متاحة.',
        'dosage': 'الجرعة:',
        'pills_per_dose': 'عدد الحبوب لكل جرعة:',
        'medicine_times': 'اوقات تناول الدواء:',
        'start_date': 'تاريخ البدء:',
        'end_date': 'تاريخ الانتهاء:',
        'condition': 'تعليمات تناول الدواء:',
      },
    };

    final texts = _localizedTexts[currentLanguage]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(texts['title']!),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: patientIdInitialized
          ? StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('ActivePatient')
                  .doc(patientId)
                  .collection('PatientMedicine')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('حدث خطأ: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text(texts['no_medications']!));
                }

                if (snapshot.hasData) {
                  return ListView.builder(
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      var doc = snapshot.data!.docs[index];
                      var medication = doc.data() as Map<String, dynamic>;

                      return Card(
                        key: Key(doc.id),
                        margin: const EdgeInsets.all(10),
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (medication['MedicineImageUrl'] != null)
                                Image.network(
                                  medication['MedicineImageUrl'],
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              const SizedBox(height: 10),
                              Text(
                                medication['MedicineName'] ?? 'اسم الدواء غير معروف',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${texts['dosage']} ${medication['MedicineDosage'] ?? 'الجرعة غير معروفة'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${texts['pills_per_dose']} ${medication['NumberOfPillsPerDose'] ?? 'لا يوجد'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              ),
                            
                              const SizedBox(height: 10),
                              Text(
                                '${texts['medicine_times']} ${(medication['MedicineTime'] as List<dynamic>?)?.map((time) => convertUtcToOmanTime(time)).join(', ') ?? 'الوقت غير معروف'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${texts['start_date']} ${DateFormat('yyyy-MM-dd').format((medication['StartDate'] as Timestamp).toDate())}',
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${texts['end_date']} ${DateFormat('yyyy-MM-dd').format((medication['EndDate'] as Timestamp).toDate())}',
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${texts['condition']} ${medication['Medication Instructions'] ?? 'الحالة غير معروفة'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                } else {
                  return Center(child: Text(texts['no_medications']!));
                }
              },
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}