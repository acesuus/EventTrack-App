const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

// Server-side double check of each new attendance record's on-time/late call.
// It only flags disagreements for the admin; it never changes status or points,
// which the app and firestore.rules already enforce (and which also depend on
// time away and check-outs that the server can't see).
// Must match AttendancePolicy.determineInitialStatus / firstRequirementOf.
exports.validateAttendance = functions.firestore
    .document("attendance/{docId}")
    .onCreate(async (snap) => {
      const record = snap.data();
      if (!record.eventId || !record.timeIn || record.manualOverride) return null;

      const eventDoc = await admin.firestore()
          .collection("events").doc(record.eventId).get();
      const event = eventDoc.data();
      if (!event || !event.startTime) return null;

      const firstRequirement = event.eventType === "type1_in_out" ?
        (event.morningRequirement || "both") :
        (event.continuousRequirement || "both");
      const cutoffMs = event.startTime.toMillis() +
        (event.lateCutoffMinutes || 15) * 60 * 1000;
      const expected = firstRequirement === "out" ||
        record.timeIn.toMillis() <= cutoffMs ? "Present" : "Late";

      await snap.ref.update({
        isServerValidated: true,
        serverExpectedInitialStatus: expected,
        serverStatusMismatch: (record.initialStatus || record.status) !== expected,
        serverValidationTimestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      return null;
    });
