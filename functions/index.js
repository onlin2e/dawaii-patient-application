const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
admin.initializeApp();
const markMissed = require("./markMissedMedicines");

exports.markMissedMedicines = markMissed.markMissedMedicines;


exports.scheduledImmediateReminders = onSchedule("every 1 minutes",
    async (event) => {
      const now = admin.firestore.Timestamp.now();
      const remindersSnapshot = await admin.firestore()
          .collection("ImmediateReminders")
          .where("scheduledTime", "<=", now)
          .get();

      console.log(`تم العثور على ${remindersSnapshot.size} تذكيرات مجدولة.`);

      const promises = [];
      remindersSnapshot.forEach((doc) => {
        const reminderData = doc.data();
        const {medicineName, deviceToken, userId, medicineId} = reminderData;

        console.log(`معالجة تذكير للمريض: ${userId}
             ، للدواء: ${medicineId}، في الوقت المجدول:
             ${reminderData.scheduledTime.toDate()}`);

        const payload = {
          notification: {
            title: "تذكير بالدواء!",
            body: `تذكير بأخذ دواء: ${medicineName}`,
          },
          token: deviceToken,
        };

        const sendPromise = admin.messaging().send(payload)
            .then((response) => {
              console.log("تم إرسال الإشعار بنجاح:", response);

              return doc.ref.delete();
            })
            .catch((error) => {
              console.error("خطأ في إرسال الإشعار:", error);
              return null;
            });

        promises.push(sendPromise);
      });

      await Promise.all(promises.filter((p) => p !== null));

      console.log("تمت معالجة جميع التذكيرات المجدولة.");
      return null;
    });
