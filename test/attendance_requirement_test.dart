import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:event_track/attendance_policy.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp at(int hour, [int minute = 0]) =>
    Timestamp.fromDate(DateTime(2026, 11, 4, hour, minute));

void main() {
  group('Time In/Out session requirements', () {
    final event = {
      'eventType': AttendancePolicy.eventTypeInOut,
      'basePoints': 10,
      'startTime': at(8),
      'endTime': at(17),
      'morningStartTime': at(8),
      'morningEndTime': at(12),
      'afternoonStartTime': at(13),
      'afternoonEndTime': at(17),
      'morningRequirement': AttendancePolicy.requireIn,
      'afternoonRequirement': AttendancePolicy.requireOut,
    };
    final halves = AttendancePolicy.inOutHalves(event);

    Map<String, dynamic>? verify(
      Map<String, dynamic> data,
      Timestamp time, {
      bool checkOut = false,
    }) => AttendancePolicy.verifyInOutAttendance(
      existing: data,
      verifiedAt: time,
      halves: halves,
      isInside: true,
      checkOutRequested: checkOut,
    );

    test('time in only + time out only completes as Present', () {
      var data = verify({}, at(8, 5))!;
      expect(
        verify(data, at(11, 50), checkOut: true),
        isNull,
        reason: 'a time-in-only session has no check-out',
      );
      expect(
        verify(data, at(13, 5)),
        isNull,
        reason: 'a time-out-only session ignores check-ins',
      );
      expect(
        verify(data, at(16, 30), checkOut: true),
        isNull,
        reason: 'time out opens 15 min before the end',
      );
      data = verify(data, at(16, 50), checkOut: true)!;
      expect(data['timeOut'], at(16, 50));
      expect(data['status'], 'Present');
    });

    test('skipping the time-out-only session is Partial', () {
      final data = verify({}, at(8, 5))!;
      final done = AttendancePolicy.finalizeIfEnded(
        data,
        event,
        DateTime(2026, 11, 4, 17, 1),
      )!;
      expect(done['status'], 'Partial');
    });

    test('a first session that only needs a time out is never Late', () {
      final outFirst = AttendancePolicy.inOutHalves({
        ...event,
        'morningRequirement': AttendancePolicy.requireOut,
      });
      final data = AttendancePolicy.verifyInOutAttendance(
        existing: {},
        verifiedAt: at(11, 50),
        halves: outFirst,
        isInside: true,
        checkOutRequested: true,
      )!;
      expect(data['initialStatus'], 'Present');
    });
  });

  group('Continuous stay requirements', () {
    final base = {
      'eventType': AttendancePolicy.eventTypeContinuous,
      'basePoints': 20,
      'startTime': at(13),
      'endTime': at(16),
    };

    test('time in only ignores leaving early', () {
      final event = {
        ...base,
        'continuousRequirement': AttendancePolicy.requireIn,
      };
      Map<String, dynamic>? verify(
        Map<String, dynamic> d,
        Timestamp t,
        bool inside,
      ) => AttendancePolicy.verifyContinuousAttendance(
        existing: d,
        verifiedAt: t,
        eventStart: DateTime(2026, 11, 4, 13),
        isInside: inside,
        requirement: AttendancePolicy.requireIn,
      );
      var data = verify({}, at(13, 2), true)!;
      data = verify(data, at(13, 10), false) ?? data;
      data = verify(data, at(15), false) ?? data;
      expect(data['status'], 'Present');
      final done = AttendancePolicy.finalizeIfEnded(
        data,
        event,
        DateTime(2026, 11, 4, 16, 1),
      )!;
      expect(done['status'], 'Present');
      expect(done['pointsAwarded'], 20);
    });

    test('time out only records once inside near the end', () {
      Map<String, dynamic>? verify(Timestamp t) =>
          AttendancePolicy.verifyContinuousAttendance(
            existing: {},
            verifiedAt: t,
            eventStart: DateTime(2026, 11, 4, 13),
            isInside: true,
            requirement: AttendancePolicy.requireOut,
            eventEnd: DateTime(2026, 11, 4, 16),
          );
      expect(verify(at(13, 5)), isNull);
      final data = verify(at(15, 50))!;
      expect(data['status'], 'Present');
      expect(data['timeOut'], at(15, 50));
    });
  });

  test('unknown or missing requirement means both', () {
    expect(AttendancePolicy.requirementOf({}, 'morningRequirement'), 'both');
    expect(
      AttendancePolicy.requirementOf({
        'morningRequirement': 'x',
      }, 'morningRequirement'),
      'both',
    );
  });
}
