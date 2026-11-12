import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of a school year rollover check.
class SchoolYearRolloverResult {
  final bool rolledOver;
  final String schoolYear;
  final int promoted;
  final int graduated;

  const SchoolYearRolloverResult({
    required this.rolledOver,
    required this.schoolYear,
    this.promoted = 0,
    this.graduated = 0,
  });
}

/// Handles automatic year level promotion of students when a new school year starts.
///
/// A school year starts every [startMonth] (August). The last processed school year
/// is stored in `settings/schoolYear` so promotion only happens once per school year.
class SchoolYearService {
  static const int startMonth = DateTime.august;
  static const int maxYearLevel = 4;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _firestore.collection('settings').doc('schoolYear');

  /// Returns the starting calendar year of the current school year (e.g. 2026 for SY 2026-2027).
  static int currentSchoolYearStart([DateTime? now]) {
    now ??= DateTime.now();
    return now.month >= startMonth ? now.year : now.year - 1;
  }

  static String schoolYearLabel(int startYear) => '$startYear-${startYear + 1}';

  /// Checks whether a new school year has started and, if so, promotes every student.
  /// Safe to call on every app launch.
  static Future<SchoolYearRolloverResult> checkAndRollover() async {
    final currentStart = currentSchoolYearStart();
    final label = schoolYearLabel(currentStart);

    // Claim the rollover atomically so it only runs once even with multiple admins.
    final int yearsElapsed = await _firestore.runTransaction<int>((tx) async {
      final snap = await tx.get(_settingsRef);
      final lastStart = (snap.data()?['lastPromotedSchoolYear'] as num?)
          ?.toInt();

      if (lastStart == null) {
        // First run: record the current school year without promoting existing data.
        tx.set(_settingsRef, {
          'lastPromotedSchoolYear': currentStart,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return 0;
      }

      if (lastStart >= currentStart) return 0;

      tx.set(_settingsRef, {
        'lastPromotedSchoolYear': currentStart,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return currentStart - lastStart;
    });

    if (yearsElapsed <= 0) {
      return SchoolYearRolloverResult(rolledOver: false, schoolYear: label);
    }

    // Promote both the imported list and students' own profiles.
    await _promoteStudents('students', yearsElapsed);
    final counts = await _promoteStudents('users', yearsElapsed);
    return SchoolYearRolloverResult(
      rolledOver: true,
      schoolYear: label,
      promoted: counts.promoted,
      graduated: counts.graduated,
    );
  }

  /// Increments the year level in each student's `yearBlock` (e.g. "1-A" -> "2-A").
  /// Students who go past [maxYearLevel] have graduated and are removed.
  static Future<({int promoted, int graduated})> _promoteStudents(
    String collection,
    int yearsElapsed,
  ) async {
    final students = await _firestore.collection(collection).get();
    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    int promoted = 0;
    int graduated = 0;

    for (final doc in students.docs) {
      final yearBlock = (doc.data()['yearBlock'] ?? '').toString().trim();
      final match = RegExp(r'^(\d+)(.*)$').firstMatch(yearBlock);
      if (match == null) continue; // Unknown format, leave untouched.

      final currentLevel = int.parse(match.group(1)!);
      final newLevel = currentLevel + yearsElapsed;
      if (newLevel > maxYearLevel) {
        batch.delete(doc.reference);
        graduated++;
      } else {
        batch.update(doc.reference, {
          'yearBlock': '$newLevel${match.group(2)}',
        });
        promoted++;
      }
      batchCount++;

      if (batchCount == 499) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) await batch.commit();
    return (promoted: promoted, graduated: graduated);
  }
}
