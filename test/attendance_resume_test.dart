import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:event_track/attendance_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 4, 13);
  final joinedAt = Timestamp.fromDate(start.add(const Duration(minutes: 5)));
  final resumedAt = Timestamp.fromDate(start.add(const Duration(minutes: 20)));

  Map<String, dynamic> join() => AttendancePolicy.verifyInOutAttendance(
    existing: {
      'eventId': 'event-1',
      'studentId': 'student-1',
      'eventType': AttendancePolicy.eventTypeInOut,
    },
    verifiedAt: joinedAt,
    eventStart: start,
    isInside: true,
  );

  test('returning from dashboard preserves the original active attendance', () {
    final joined = join();
    // The dashboard normalizes the saved record before resuming it.
    final record = AttendanceSessionRecord.fromFirestore(
      joined,
    ).bootstrapLegacyIfNeeded(fallbackStart: joinedAt);
    final persisted = {
      ...joined,
      ...record.toFirestoreFields(
        studentId: 'student-1',
        eventId: 'event-1',
        eventTitle: 'Test event',
      ),
    };
    final resumed = AttendancePolicy.verifyInOutAttendance(
      existing: persisted,
      verifiedAt: resumedAt,
      eventStart: start,
      isInside: true,
    );
    expect(resumed, persisted);
    expect(resumed['timeIn'], joinedAt);
    expect(resumed['status'], 'Present');
    expect(resumed['timeOut'], isNull);
    expect(
      AttendancePolicy.canJoinExistingAttendance(resumed['timeOut']),
      isTrue,
    );
    expect(joined.containsKey('sessions'), isFalse);
  });

  test(
    'only explicit checkout inside the venue finalizes the joined event',
    () {
      final saved = join();
      final checkedOut = AttendancePolicy.verifyInOutAttendance(
        existing: saved,
        verifiedAt: resumedAt,
        eventStart: start,
        isInside: true,
        checkOutRequested: true,
      );
      expect(checkedOut['timeIn'], joinedAt);
      expect(checkedOut['timeOut'], resumedAt);
      expect(
        AttendancePolicy.canJoinExistingAttendance(checkedOut['timeOut']),
        isFalse,
      );
      expect(saved['timeOut'], isNull);
    },
  );

  test('outside verification and rejected checkout keep membership active', () {
    for (final checkOut in [false, true]) {
      final saved = join();
      final result = AttendancePolicy.verifyInOutAttendance(
        existing: saved,
        verifiedAt: resumedAt,
        eventStart: start,
        isInside: false,
        checkOutRequested: checkOut,
      );
      expect(result, saved);
      expect(result['timeOut'], isNull);
    }
  });

  test('resuming finalized attendance cannot reopen or overwrite it', () {
    final saved = {...join(), 'timeOut': resumedAt};
    final result = AttendancePolicy.verifyInOutAttendance(
      existing: saved,
      verifiedAt: Timestamp.fromDate(start.add(const Duration(minutes: 40))),
      eventStart: start,
      isInside: true,
      checkOutRequested: true,
    );
    expect(result, saved);
  });
}
