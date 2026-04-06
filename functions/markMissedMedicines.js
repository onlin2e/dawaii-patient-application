// functions/markMissedMedicines.js
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

/**

 * @param {admin.firestore.Timestamp} firestoreTimestamp Timestamp.
 * @return {Date | null}
 */
function getStartOfLocalDayAsUtc(firestoreTimestamp) {
  if (!firestoreTimestamp) return null;
  const date = firestoreTimestamp.toDate();


  const offsetInMs = 4 * 60 * 60 * 1000;

  const localTimeAdjusted = new Date(date.getTime() + offsetInMs);

  return new Date(Date.UTC(localTimeAdjusted.getUTCFullYear(),
      localTimeAdjusted.getUTCMonth(), localTimeAdjusted.getUTCDate()));
}


exports.markMissedMedicines = onSchedule("every 15 minutes", async (event) => {
  const firestore = admin.firestore();
  const nowUtc = admin.firestore.Timestamp.now().toDate();

  console.log(`بدء دالة markMissedMedicines في ${nowUtc.toISOString()} (UTC)`);
  console.log(`Now (UTC): ${nowUtc.toISOString()}
  , Timestamp: ${nowUtc.getTime()}`);

  try {
    const activePatientsSnapshot =
     await firestore.collection("ActivePatient").get();

    if (activePatientsSnapshot.empty) {
      console.log("لا يوجد مرضى نشطون للتحقق منهم.");
      return null;
    }

    for (const patientDoc of activePatientsSnapshot.docs) {
      const patientId = patientDoc.id;
      console.log(`التحقق من الأدوية للمريض: ${patientId}`);

      const patientMedicinesSnapshot =
       await firestore.collection("ActivePatient")
           .doc(patientId)
           .collection("PatientMedicine")
           .get();

      if (patientMedicinesSnapshot.empty) {
        console.log(`المريض ${patientId} ليس لديه أدوية.`);
        continue;
      }

      for (const medicineDoc of patientMedicinesSnapshot.docs) {
        const medicineData = medicineDoc.data();
        const medicineId = medicineDoc.id;

        console.log(`-- فحص الدواء: ${medicineId} للمريض: ${patientId}`);

        // اطبع القيم الأصلية من Firestore لـ StartDate و EndDate
        console.log(`   Firestore StartDate: ${medicineData.StartDate ?
             medicineData.StartDate.toDate().toISOString() : "N/A"}`);
        console.log(`   Firestore EndDate: ${medicineData.EndDate ?
             medicineData.EndDate.toDate().toISOString() : "N/A"}`);
        console.log(`   MedicineTime from Firestore:
             ${JSON.stringify(medicineData.MedicineTime)}`);


        const startDate = medicineData.StartDate ?
          medicineData.StartDate.toDate() : null;
        const endDate = medicineData.EndDate ?
          medicineData.EndDate.toDate() : null;
        const medicineTimes = medicineData.MedicineTime || [];

        if (!startDate || !endDate || !medicineTimes.length) {
          console.log(`   تخطي الدواء ${medicineId}
            : بيانات غير كاملة (StartDate/EndDate/MedicineTime مفقودة).`);
          continue;
        }

        // هذا التحقق يضمن أن الدواء نشط في الوقت الحالي (nowUtc)
        if (nowUtc < startDate || nowUtc > endDate) {
          console.log(`   تخطي الدواء ${medicineId}
            : الدواء خارج فترة الصلاحية الكلية بناءً على الوقت الحالي.`);
          continue;
        }

        // هنا التعديل: استخدام الدالة المساعدة الجديدة لـ datesToCheck
        const datesToCheck = [
          getStartOfLocalDayAsUtc(admin.firestore.Timestamp.fromDate(nowUtc)),
          getStartOfLocalDayAsUtc(admin.firestore.Timestamp
              .fromDate(new Date(nowUtc.getTime() - (24 * 60 * 60 * 1000)))),
        ];
        console.log(`   Dates to check (adjusted UTC):
             ${datesToCheck.map((d) =>
    d.toISOString().split("T")[0]).join(", ")}`);


        for (const timeUtc of medicineTimes) {
          try {
            // هنا التعديل: استخدم Date.UTC لبناء scheduledDateTimeUtc
            const [hours, minutes] = timeUtc.split(":").map(Number);

            for (const datePart of datesToCheck) {
              const scheduledDateTimeUtc = new Date(
                  Date.UTC(
                      datePart.getUTCFullYear(),
                      datePart.getUTCMonth(),
                      datePart.getUTCDate(),
                      hours,
                      minutes,
                      0,
                      0,
                  ),
              );

              const startDateOnly =
               getStartOfLocalDayAsUtc(medicineData.StartDate);
              const endDateOnly =
               getStartOfLocalDayAsUtc(medicineData.EndDate);
              const scheduledDateOnly =
               new Date(Date.UTC(scheduledDateTimeUtc.getUTCFullYear(),
                   scheduledDateTimeUtc.getUTCMonth(),
                   scheduledDateTimeUtc.getUTCDate()));

              console.log(`      Debugging dates (UTC): ScheduledDateOnly=
                ${scheduledDateOnly.toISOString().split("T")[0]},
               StartDateOnly=${startDateOnly.toISOString()
      .split("T")[0]}, EndDateOnly=
               ${endDateOnly.toISOString().split("T")[0]}`);


              if (scheduledDateOnly < startDateOnly ||
                 scheduledDateOnly > endDateOnly) {
                console.log(`         تخطي: الموعد المجدول
                    ${scheduledDateTimeUtc.toISOString()}
                 خارج نطاق صلاحية الدواء. (Compare UTC:
                   ${scheduledDateOnly.toISOString().split("T")[0]}
                  vs ${startDateOnly.toISOString().split("T")[0]} to 
                  ${endDateOnly.toISOString().split("T")[0]})`);
                continue;
              } else {
                console.log(`         الموعد المجدول 
                    ${scheduledDateTimeUtc.toISOString()}
                     داخل نطاق صلاحية الدواء.`);
              }
              // *** نهاية التعديل الرئيسي ***

              const missedThresholdTimeUtc =
               new Date(scheduledDateTimeUtc.getTime() + (90 * 60 * 1000));

              console.log(`      موعد مجدول (Full UTC):
                 ${scheduledDateTimeUtc.toISOString()}
              , عتبة الفوات: ${missedThresholdTimeUtc.toISOString()}`);

              if (scheduledDateTimeUtc > nowUtc) {
                console.log(`         تخطي: الموعد المجدول في المستقبل
                    (${scheduledDateTimeUtc.toISOString()}
                 > ${nowUtc.toISOString()}).`);
                continue;
              }

              const intakeLogDocId =
                `${medicineId}_${scheduledDateTimeUtc.getTime()}`;

              const intakeLogRef = firestore.collection("ActivePatient")
                  .doc(patientId)
                  .collection("PatientMedicine")
                  .doc(medicineId)
                  .collection("MedicineIntakeLogs")
                  .doc(intakeLogDocId);

              const intakeLogSnapshot = await intakeLogRef.get();
              const intakeData = intakeLogSnapshot.data();

              console.log(`         سجل الجرعة
                ${intakeLogDocId} موجود: ${intakeLogSnapshot.exists}
                , Taken: ${intakeData ? intakeData.taken : "N/A"}, Data:
                ${JSON.stringify(intakeData)}`);

              if (!intakeLogSnapshot.exists &&
                 nowUtc >= missedThresholdTimeUtc) {
                console.log(`***** تسجيل دواء فائت جديد: المريض ${patientId}` +
                      `, الدواء ${medicineId}` +
                      `, الوقت المجدول ${scheduledDateTimeUtc.toISOString()}`);
                await intakeLogRef.set({
                  scheduledTime: admin.firestore.
                      Timestamp.fromDate(scheduledDateTimeUtc),
                  taken: false,
                  missedReason: "تجاوز وقت الدواء تلقائياً (CF)",
                  timestamp: admin.firestore.Timestamp.fromDate(nowUtc),
                }, {merge: true});
              } else if (intakeLogSnapshot.exists &&
                 intakeLogSnapshot.data().taken ===
               false && nowUtc >= missedThresholdTimeUtc) {
                console.log(`تحديث سبب الفوات (موجود وغير مأخوذ): المريض
                    ${patientId}` +
                      `, الدواء ${medicineId}` +
                      `, الوقت المجدول 
                      ${scheduledDateTimeUtc.toISOString()}`);
                await intakeLogRef.set({
                  missedReason: "تجاوز وقت الدواء تلقائياً (CF - تحديث)",
                  timestamp: admin.firestore.Timestamp.fromDate(nowUtc),
                }, {merge: true});
              } else {
                console.log(`         تخطي: الدواء 
                    ${medicineId} للمريض ${patientId}
                     (تم أخذه، أو لم يحن وقته، أو حالة غير متوقعة).`);
              }
            }
          } catch (e) {
            console.error(`خطأ في معالجة الوقت ${timeUtc}` +
                  `للدواء ${medicineId}:`, e);
          }
        }
      }
    }
    console.log("اكتمال دالة markMissedMedicines بنجاح.");
    return null;
  } catch (error) {
    console.error("خطأ عام في دالة markMissedMedicines:", error);
    throw new Error("فشل في وضع علامة على الأدوية الفائتة.");
  }
});
