const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.validateAttendance = functions.firestore
    .document("attendance/{docId}")
    .onCreate(async (snap, context) => {
        const attendanceData = snap.data();
        const eventId = attendanceData.eventId;
        const studentId = attendanceData.studentId;
        const timeIn = attendanceData.timeIn; // Firestore Timestamp

        if (!eventId || !studentId || !timeIn) {
            console.error("Missing required fields (eventId, studentId, timeIn)");
            return null;
        }

        try {
            const eventRef = admin.firestore().collection("events").doc(eventId);
            const eventDoc = await eventRef.get();

            if (!eventDoc.exists) {
                console.error(`Event ${eventId} not found`);
                return null;
            }

            const eventData = eventDoc.data();
            const startTime = eventData.startTime; // Firestore Timestamp
            const lateCutoffMinutes = eventData.lateCutoffMinutes || 15;

            if (!startTime) {
                console.error("Event document is missing startTime");
                return null;
            }

            // Convert Timestamps to JavaScript Date objects
            const timeInDate = timeIn.toDate();
            const startTimeDate = startTime.toDate();

            // Calculate differences in minutes
            const diffInMs = timeInDate.getTime() - startTimeDate.getTime();
            const diffInMinutes = diffInMs / (1000 * 60);

            // True Authority logic matching Dart's AttendancePolicy
            let serverStatus = "Present";
            if (diffInMinutes > lateCutoffMinutes) {
                serverStatus = "Late";
            }
            
            // Note: Cloud Functions run asynchronously.
            // When offline, this triggers once the device comes back online and syncs the doc.
            const updatePayload = {
                status: serverStatus,
                isServerValidated: true,
                serverValidationTimestamp: admin.firestore.FieldValue.serverTimestamp()
            };

            await snap.ref.update(updatePayload);
            console.log(`Validated attendance for ${studentId} at ${eventId}: ${serverStatus}`);
            
            return null;

        } catch (error) {
            console.error("Error validating attendance:", error);
            return null;
        }
    });
