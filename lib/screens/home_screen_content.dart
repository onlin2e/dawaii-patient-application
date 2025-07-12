import 'package:flutter/material.dart';
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:med_ad_app/screens/medication_screen.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';







class HomeScreenContent extends StatefulWidget {

  
  const HomeScreenContent({super.key
  
  });

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
   String patientName = '...';
   Set<String> confirmedMedicineIds = <String>{};
   bool _isConfirming = false;
     Map<String, bool> _remindLaterButtonDisabled = {};

   Map<String, int> _remindLaterCounts = {};
  Map<String, bool> _isRemindingLater = {};
  late Future<List<Map<String, dynamic>>> _medicinesFuture; 


  

//get name
  @override
  void initState() {
    super.initState();
    fetchPatientName(); 
    // _loadConfirmedMedicines();
      _loadRemindLaterStates();
     _medicinesFuture = fetchScheduledMedicines(); // تهيئة Future عند بدء التشغيل


  }

Future<void> _loadRemindLaterStates() async {
  final prefs = await SharedPreferences.getInstance();
  final meds = await fetchScheduledMedicines(); // أو أي طريقة تحصل بها على قائمة الأدوية


  for (var med in meds) {
    final medicineId = med['medicineId'] as String;
    final isDisabled = prefs.getBool('remindLaterDisabled_$medicineId') ?? false;
    final expiryTimeString = prefs.getString('remindLaterExpiry_$medicineId');

    if (isDisabled && expiryTimeString != null) {
      final expiryTime = DateTime.parse(expiryTimeString);
      if (expiryTime.isAfter(DateTime.now())) {
        setState(() {
          _remindLaterButtonDisabled[medicineId] = true;
        });
        final remainingTime = expiryTime.difference(DateTime.now());
        Future.delayed(remainingTime, () async {
          final currentExpiry = await prefs.getString('remindLaterExpiry_$medicineId');
          if (currentExpiry == expiryTimeString && mounted) {
            setState(() {
              _remindLaterButtonDisabled[medicineId] = false;
            });
            await prefs.remove('remindLaterDisabled_$medicineId');
            await prefs.remove('remindLaterExpiry_$medicineId');
          }
        });
      } else {
        // إذا انقضى الوقت أثناء عدم تشغيل التطبيق، قم بإزالة الحالة
        await prefs.remove('remindLaterDisabled_$medicineId');
        await prefs.remove('remindLaterExpiry_$medicineId');
      }
    }
  }
}
  // استرجاع patientId من SharedPreferences
Future<String> getPatientId() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString('patientId') ?? ''; // إرجاع قيمة فارغة إذا لم يتم العثور عليها

  
}

Future<String?> getDeviceToken() async {
  try {
    return await FirebaseMessaging.instance.getToken();
  } catch (e) {
    print("Error getting Firebase device token: $e");
    return null;
  }
}

//remind me later
void _remindMeLater(Map<String, dynamic> med) async {
    final medicineId = med['medicineId'] as String;
    final disableDuration = const Duration(minutes: 30);
    final expiryTime = DateTime.now().add(disableDuration).toIso8601String();
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _remindLaterButtonDisabled[medicineId] = true;
    });

    // حفظ حالة الزر ووقت الانتهاء في shared_preferences
    await prefs.setBool('remindLaterDisabled_$medicineId', true);
    await prefs.setString('remindLaterExpiry_$medicineId', expiryTime);

    // قم بتشغيل التذكير الفوري (الكود السابق الخاص بإنشاء التذكير)
    final medicineName = med['MedicineName'] as String;
    final deviceToken = await getDeviceToken();
    final patientId = await getPatientId();

    if (deviceToken == null || deviceToken.isEmpty) {
      print('Flutter: خطأ: لم يتم الحصول على deviceToken أو كانت قيمته فارغة.');
      return;
    }

    try {
      final now = DateTime.now().toUtc();
      final scheduledTimeUtc = now.add(const Duration(minutes: 30));

      final immediateRemindersCollection =
          FirebaseFirestore.instance.collection('ImmediateReminders');

      await immediateRemindersCollection.add({
        'medicineName': medicineName,
        'deviceToken': deviceToken,
        'userId': patientId,
        'medicineId': medicineId,
        'timestamp': Timestamp.fromDate(now),
        'scheduledTime': Timestamp.fromDate(scheduledTimeUtc),
      });

      // لا تقم بإدارة _remindLaterCounts هنا إذا لم تعد تستخدمها للحد.

      // بعد نصف ساعة، قم بتمكين الزر محليًا وإزالة الحالة من SharedPreferences
      Future.delayed(disableDuration, () async {
        final currentExpiry = await prefs.getString('remindLaterExpiry_$medicineId');
        if (currentExpiry == expiryTime && mounted) {
          setState(() {
            _remindLaterButtonDisabled[medicineId] = false;
          });
          await prefs.remove('remindLaterDisabled_$medicineId');
          await prefs.remove('remindLaterExpiry_$medicineId');
        }
      });
    } catch (e) {
      print('Flutter: خطأ في إنشاء تذكير فوري: $e');
    }
  }




/////////////////////////////
Future<List<Map<String, dynamic>>> fetchScheduledMedicines() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String patientId = prefs.getString('patientId') ?? '';
  DateTime now = DateTime.now();

  List<Map<String, dynamic>> scheduledMedicines = [];

  QuerySnapshot patientMedicineSnapshot = await FirebaseFirestore.instance
      .collection('ActivePatient')
      .doc(patientId)
      .collection('PatientMedicine')
      .get();

  for (var medicineDoc in patientMedicineSnapshot.docs) {
    var medicineData = medicineDoc.data() as Map<String, dynamic>; // Good, casting here

    if (medicineData['StartDate'] == null ||
        medicineData['EndDate'] == null ||
        medicineData['nowTime'] == null) {
      continue;
    }

    DateTime startDate = (medicineData['StartDate'] as Timestamp).toDate();
    DateTime endDate = (medicineData['EndDate'] as Timestamp).toDate();
    List<dynamic> nowTimes = medicineData['nowTime'];

    if (now.isAfter(startDate.subtract(const Duration(days: 1))) &&
        now.isBefore(endDate.add(const Duration(days: 1)))) {
      for (var timeNow in nowTimes) {
        try {
          final parsedTime = DateFormat("HH:mm").parse(timeNow);
          final medicineDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            parsedTime.hour,
            parsedTime.minute,
          );

          final endTime = medicineDateTime.add(const Duration(hours: 1, minutes: 30));

          final intakeLogDocId = '${medicineDoc.id}_${medicineDateTime.millisecondsSinceEpoch}';

          final intakeLogsRef = FirebaseFirestore.instance
              .collection('ActivePatient')
              .doc(patientId)
              .collection('PatientMedicine')
              .doc(medicineDoc.id)
              .collection('MedicineIntakeLogs')
              .doc(intakeLogDocId);

          DocumentSnapshot intakeLogSnapshot = await intakeLogsRef.get();
          // *** FIX APPLIED HERE ***
          final intakeLogData = intakeLogSnapshot.data() as Map<String, dynamic>?;


          if (now.isAfter(medicineDateTime.subtract(const Duration(minutes: 1))) &&
              now.isBefore(endTime)) {
            // Check if the record exists OR if it exists but 'taken' is NOT true
            if (!intakeLogSnapshot.exists || !(intakeLogData?['taken'] == true)) {
              scheduledMedicines.add(Map<String, dynamic>.from(medicineData)
                ..['scheduledTime'] = medicineDateTime
                ..['medicineId'] = medicineDoc.id
                ..['intakeLogDocId'] = intakeLogDocId
              );
            }
          }
          // else if (medicineDateTime.isBefore(now.subtract(const Duration(minutes: 1))) &&
          //          !now.isBefore(medicineDateTime.add(const Duration(minutes: 1)))) {
          //   await intakeLogsRef.set({
          //     'scheduledTime': Timestamp.fromDate(medicineDateTime),
          //     'taken': false,
          //     'missedReason': 'تجاوز وقت الدواء دون تأكيد',
          //     'timestamp': Timestamp.fromDate(now),
          //   }, SetOptions(merge: true));
          // }
        } catch (e) {
          print('Error parsing time: $timeNow - $e');
        }
      }
    }
  }

  scheduledMedicines.sort((a, b) =>
      (a['scheduledTime'] as DateTime).compareTo(b['scheduledTime'] as DateTime));

  return scheduledMedicines;
}

 
/////confirm
// في FutureBuilder's itemBuilder:
// ...
// تأكد من تمرير intakeLogDocId
// final intakeLogDocId = med['intakeLogDocId'] as String;
// ...
// onPressed: () => _confirm(med, intakeLogDocId), // تمرير intakeLogDocId هنا
// ...

// تحديث تعريف دالة _confirm
Future<void> _confirm(Map<String, dynamic> med, String intakeLogDocId) async {
  setState(() {
    _isConfirming = true;
  });
  final medicineId = med['medicineId'];
  final scheduledTime = med['scheduledTime'] as DateTime;

  if (medicineId != null && intakeLogDocId.isNotEmpty) {
    DateTime now = DateTime.now();
    final patientId = await getPatientId();

    final intakeLogsRef = FirebaseFirestore.instance
      .collection('ActivePatient')
      .doc(patientId)
      .collection('PatientMedicine')
      .doc(medicineId)
      .collection('MedicineIntakeLogs')
      .doc(intakeLogDocId); // تحديد المستند بالـ ID الفريد

    await intakeLogsRef.set({ // استخدام set مع merge
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'takenAt': Timestamp.fromDate(now),
      'takenBy': patientId,
      'taken': true,
      'missedReason': FieldValue.delete(), // حذف حقل missedReason إذا كان موجودًا
    }, SetOptions(merge: true));

    print('تم تأكيد أخذ الدواء بمعرف: $medicineId ... وتم حفظ/تحديث السجل.');

    // بعد التأكيد بنجاح، يجب أن تحدث واجهة المستخدم.
    // الطريقة الأبسط هي إعادة تحميل الأدوية المجدولة:
    setState(() {
      _medicinesFuture = fetchScheduledMedicines(); // إعادة جلب الأدوية لتحديث القائمة
    });

  } else {
    print('خطأ: لا يمكن الحصول على معرف الدواء أو معرف السجل لحفظ سجل الأخذ.');
  }
  setState(() {
    _isConfirming = false;
  });
}

// get name
   Future<void> fetchPatientName() async {
  try {
    String patientId = await getPatientId(); // استرجاع patientId من SharedPreferences

    var snapshot = await FirebaseFirestore.instance
        .collection('ActivePatient')
        .where('patientId', isEqualTo: patientId) 
        .get();

    if (snapshot.docs.isNotEmpty) {
      String? fullName = snapshot.docs.first.data()['patientName']; 
      if (fullName != null && fullName.isNotEmpty) {
        String firstName = fullName.split(' ')[0]; 
        setState(() {
          patientName = firstName;
        });
      } else {
        setState(() {
          patientName = 'غير معروف';
        });
      }
    } else {
      setState(() {
        patientName = 'غير موجود';
      });
    }
  } catch (e) {
    setState(() {
      patientName = 'خطأ في التحميل';
    });
    print("Error fetching patient name: $e");
  }
}





  @override
  Widget build(BuildContext context) {
    final currentLanguage = Provider.of<LocaleProvider>(context).currentLanguage;
    
    
    
    

    Map<String, Map<String, String>> _localizedTexts = {
      'en': {
        'welcome': 'Welcome',
        'guest': 'Alaa',
        'to_take': 'Medicines for Today',
        'confirm': 'Confirm',
        'remind_me_later': 'Remind me later',
        'medications': 'My Medications',
      },
      'ar': {
        'welcome': 'أهلاً وسهلاً',
        'guest': 'Alaa',
        'to_take': 'الأدوية الخاصة بك لهذا اليوم',
        'confirm': 'تأكيد',
        'remind_me_later': 'قم بتذكيري لاحقًا',
        'medications': 'أدويتي',
      },
    };

    Map<String, List<String>> months = {
      'en': ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"],
      'ar': ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
    };

    Map<String, List<String>> weekdays = {
      'en': ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"],
      'ar': ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
    };

    final texts = _localizedTexts[currentLanguage]!;
    final currentDate = DateTime.now();
    final dates = List.generate(5, (index) => currentDate.add(Duration(days: index - 2)));

    

    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          texts['welcome']!,
                          style: TextStyle(fontSize: screenHeight * 0.02, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        Text(
                          patientName,
                          style: TextStyle(fontSize: screenHeight * 0.02, color: Colors.grey),
                        ),
                      ],
                    ),
                  
                  ],
                ),
              ),

              // عرض اسم الشهر والسنة بناءً على اللغة
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${months[currentLanguage]![currentDate.month - 1]} ${currentDate.year}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 106, 31, 217),
                    ),
                  ),
                ),
              ),

              SizedBox(height: 10),

              // شريط التواريخ
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: dates.map((date) {
                    final isToday = date.day == currentDate.day;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            decoration: isToday
                                ? BoxDecoration(
                                    color: Color.fromARGB(255, 106, 31, 217),
                                    borderRadius: BorderRadius.circular(10),
                                  )
                                : null,
                            child: Column(
                              children: [
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    color: isToday ? Colors.white : Color.fromARGB(255, 106, 31, 217),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  '${weekdays[currentLanguage]![date.weekday % 7]}',
                                  style: TextStyle(
                                    color: isToday ? Colors.white : Color.fromARGB(255, 106, 31, 217),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              SizedBox(height: 25),

          // القسم البنفسجي
            Expanded(
              child: Container(
                width:screenWidth,
                // margin: EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  
                  color: Color.fromARGB(255, 106, 31, 217), 
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                // child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          texts['to_take']!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                               Expanded(
                                 child: FutureBuilder(
                                                   future: fetchScheduledMedicines(),
                                                   
                                                   builder: (context, snapshot) {
                                                     
                                                     if (snapshot.connectionState == ConnectionState.waiting) {
                                                       return const Center(child: CircularProgressIndicator(color: Colors.white));
                                                     }
                                                               
                                                     if (snapshot.hasError) {
                                                       return const Center(child: Text('حدث خطأ أثناء جلب الأدوية', style: TextStyle(color: Colors.white)));
                                                     }
                                                               
                                                     final meds = snapshot.data ?? [];
                                                               
                                                     if (meds.isEmpty) {
                                                       return const Center(child: Text(' لا توجد أدوية حالياً', style: TextStyle(color: Colors.white)));
                                                     }
                                                               
                                                     return ListView.builder(
                                                      //  shrinkWrap: true,
                                                      //  physics: const NeverScrollableScrollPhysics(),
                                                       itemCount: meds.length,
                                                       itemBuilder: (context, index) {
                                                         final med = meds[index];
                                                         final name = med['MedicineName'] ?? 'اسم الدواء غير معروف';
                                                         final scheduledTime = med['scheduledTime'] as DateTime;
                                                         final dosage = med['MedicineDosage'] ?? 'غير محدد';
                                                         final condition = med['Medication Instructions'] ?? 'غير محدد';
                                                         final pillsPerDose = med['NumberOfPillsPerDose']?.toString() ?? 'غير محدد';
                                                               
                                                         return Padding(
                                                           padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                                            child: confirmedMedicineIds.contains(med['medicineId'])
                                                      ? const SizedBox.shrink() // إخفاء العنصر
                                                          : Card(
                                                             elevation: 4,
                                                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                             color: Colors.white.withOpacity(0.9), // خلفية فاتحة للبطاقة
                                                             child: Padding(
                                                               padding: const EdgeInsets.all(16.0),
                                                               child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (med['MedicineImageUrl'] != null && med['MedicineImageUrl'].isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8.0, right: 16.0),
                                            child: SizedBox(
                                              width: 100,
                                              height: 100,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: Image.network(
                                                  med['MedicineImageUrl'],
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return const Icon(Icons.image_not_supported_outlined, size: 30, color: Colors.grey);
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 10,),
                                        Text(
                                      name,
                                      style: const TextStyle(
                                        color: Color.fromARGB(255, 106, 31, 217),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    
                                    const SizedBox(height: 8),
                                    Text(
                                      'الوقت: ${DateFormat('HH:mm').format(scheduledTime)}',
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'الجرعة: $dosage',
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    Text(
                                      'عدد الحبوب: $pillsPerDose',
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    Text(
                                      'تعليمات تناول الدواء: $condition',
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                       
                                                 Expanded(
  child: ElevatedButton(
    onPressed: _isConfirming // هذا يمنع الضغط المتعدد أثناء عملية التأكيد
        ? null
        : () async {
            setState(() {
              _isConfirming = true;
            });
            final medicineId = med['medicineId'];
            final scheduledTime = med['scheduledTime'] as DateTime;
            // تأكد من تمرير intakeLogDocId
            final intakeLogDocId = med['intakeLogDocId'] as String; // <--- هنا يتم استخراج intakeLogDocId

            if (medicineId != null && intakeLogDocId.isNotEmpty) { // <--- التأكد من أن intakeLogDocId موجود
              DateTime now = DateTime.now();
              final patientId = await getPatientId();

              final intakeLogsRef = FirebaseFirestore.instance
                  .collection('ActivePatient')
                  .doc(patientId)
                  .collection('PatientMedicine')
                  .doc(medicineId)
                  .collection('MedicineIntakeLogs')
                  .doc(intakeLogDocId); // <--- استخدام intakeLogDocId هنا لتحديد المستند

              await intakeLogsRef.set({ // استخدام set مع merge لتحديث أو إنشاء السجل
                'scheduledTime': Timestamp.fromDate(scheduledTime),
                'takenAt': Timestamp.fromDate(now),
                'takenBy': patientId,
                'taken': true,
                'missedReason': FieldValue.delete(),
              }, SetOptions(merge: true));

              print('تم تأكيد أخذ الدواء بمعرف: $medicineId ... وتم حفظ/تحديث السجل.');

              // بعد التأكيد بنجاح، يجب أن تحدث واجهة المستخدم.
              // الطريقة الأبسط هي إعادة تحميل الأدوية المجدولة:
              setState(() {
                _medicinesFuture = fetchScheduledMedicines(); // إعادة جلب الأدوية لتحديث القائمة
              });
            } else {
              print('خطأ: لا يمكن الحصول على معرف الدواء أو معرف السجل لحفظ سجل الأخذ.');
            }
            setState(() {
              _isConfirming = false;
            });
          },
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.green.shade400,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(vertical: 12),
    ),
    child: Text(texts['confirm']!),
  ),
),
                                        const SizedBox(width: 16),
                                        /// زر "ذكرني لاحقا"
                                        Expanded(
                                                 child: ElevatedButton(
                                                   onPressed: _remindLaterButtonDisabled[med['medicineId']] == true
                                                       ? null
                                                       : () => _remindMeLater(med),
                                                   style: ElevatedButton.styleFrom(
                                                     backgroundColor: _remindLaterButtonDisabled[med['medicineId']] == true
                                                         ? Colors.grey.shade400 // لون فضي عند التعطيل
                                                         : Colors.orange.shade400,
                                                     foregroundColor: Colors.white,
                                                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                     padding: const EdgeInsets.symmetric(vertical: 12),
                                                   ),
                                                   child: _remindLaterButtonDisabled[med['medicineId']] == true
                                                       ? const Text('تم التذكير') 
                                                       : Text(texts['remind_me_later']!),
                                                 ),
                                               ),
                                      ],
                                    ),
                                  ],
                                                               ),
                                                             ),
                                                           ),
                                                         );
                                                       },
                                                     );
                                                   },
                                                               ),
                               )
                              
                              
                              
                    ],
                  ),
                // ),
              ),
            ),
          
        ],
      ),
    ),
  // ),
);

  }
}
