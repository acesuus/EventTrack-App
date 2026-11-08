import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:event_track/attendance_policy.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp at(int hour, [int minute = 0]) =>
    Timestamp.fromDate(DateTime(2026, 11, 4, hour, minute));

void main() {
  group('Time In/Out halves', () {
    final event = {
      'eventType': AttendancePolicy.eventTypeInOut,
      'basePoints': 10,
      'startTime': at(8),
      'endTime': at(17),
      'morningStartTime': at(8),
      'morningEndTime': at(12),
      'afternoonStartTime': at(13),
      'afternoonEndTime': at(17),
    };
    final halves = AttendancePolicy.inOutHalves(event);

    Map<String, dynamic>? verify(
      Map<String, dynamic> data,
      Timestamp time, {
      bool checkOut = false,
      bool inside = true,
    }) => AttendancePolicy.verifyInOutAttendance(
      existing: data,
      verifiedAt: time,
      halves: halves,
      isInside: inside,
      checkOutRequested: checkOut,
    );

    test('both halves checked in and out keeps the initial status', () {
      var data = verify({}, at(8, 5))!;
      expect(data['status'], 'Present');
      expect(verify(data, at(9), checkOut: true), isNull,
          reason: 'check-out opens 15 min before the half ends');
      data = verify(data, at(11, 50), checkOut: true)!;
      expect(verify(data, at(12, 30)), isNull, reason: 'lunch break');
      data = verify(data, at(13, 2))!;
      data = verify(data, at(16, 55), checkOut: true)!;
      expect(data['timeOut'], at(16, 55));
      expect(data['status'], 'Present');
    });

    test('a student who misses a half ends as Partial', () {
      var data = verify({}, at(8, 30))!;
      expect(data['status'], 'Late');
      data = verify(data, at(11, 55), checkOut: true)!;
      final done = AttendancePolicy.finalizeIfEnded(
        data,
        event,
        DateTime(2026, 11, 4, 17, 1),
      )!;
      expect(done['status'], 'Partial');
      expect(done['pointsAwarded'], 5);
      expect(done['timeOut'], at(17));
    });

    test('outside readings and finalized records never change', () {
      expect(verify({}, at(8, 5), inside: false), isNull);
      final finished = {...verify({}, at(8, 5))!, 'timeOut': at(17)};
      expect(verify(finished, at(13, 5)), isNull);
      expect(
        AttendancePolicy.finalizeIfEnded(
          finished,
          event,
          DateTime(2026, 11, 4, 18),
        ),
        isNull,
      );
    });
  });

  group('Continuous stay', () {
    final event = {
      'eventType': AttendancePolicy.eventTypeContinuous,
      'basePoints': 20,
      'startTime': at(13),
      'endTime': at(16),
    };

    Map<String, dynamic>? verify(
      Map<String, dynamic> data,
      Timestamp time, {
      bool inside = true,
    }) => AttendancePolicy.verifyContinuousAttendance(
      existing: data,
      verifiedAt: time,
      eventStart: DateTime(2026, 11, 4, 13),
      isInside: inside,
    );

    Map<String, dynamic> finish(Map<String, dynamic> data) =>
        AttendancePolicy.finalizeIfEnded(
          data,
          event,
          DateTime(2026, 11, 4, 16, 1),
        )!;

    Map<String, dynamic> stayUntil(
      Map<String, dynamic> data,
      int fromMinute,
      int toMinute,
    ) {
      for (var m = fromMinute; m <= toMinute; m += 1) {
        data = verify(data, at(13, 0).plusMinutes(m)) ?? data;
      }
      return data;
    }

    test('staying the whole event is Present with full points', () {
      var data = verify({}, at(13, 5))!;
      expect(verify(data, at(13, 6)), isNull, reason: 'heartbeat throttled');
      data = stayUntil(data, 6, 180);
      final done = finish(data);
      expect(done['status'], 'Present');
      expect(done['pointsAwarded'], 20);
    });

    test('leaving for more than 15 minutes ends as Partial', () {
      var data = verify({}, at(13, 5))!;
      data = stayUntil(data, 5, 55);
      data = verify(data, at(14), inside: false)!;
      data = verify(data, at(14, 30))!;
      data = stayUntil(data, 90, 180);
      final done = finish(data);
      expect(done['totalOutsideSeconds'], 30 * 60);
      expect(done['status'], 'Partial');
      expect(done['pointsAwarded'], 10);
    });

    test('closing the app counts as leaving once readings go stale', () {
      var data = verify({}, at(13, 5))!;
      data = stayUntil(data, 5, 30);
      // No more readings: the session closes 5 min after the last one.
      final done = finish(data);
      expect(done['status'], 'Partial');
      final sessions = done['sessions'] as List;
      expect(
        (sessions.last['timeOut'] as Timestamp).toDate(),
        DateTime(2026, 11, 4, 13, 34),
      );
    });

    test('returning after the app was closed records the gap as away', () {
      var data = verify({}, at(13, 5))!;
      data = verify(data, at(14, 30))!;
      expect((data['sessions'] as List).length, 2);
      expect(data['totalOutsideSeconds'], (85 - 5) * 60);
    });
  });

  test('points follow the event base points', () {
    expect(AttendancePolicy.pointsFor('Present', 15), 15);
    expect(AttendancePolicy.pointsFor('Late', 15), 8);
    expect(AttendancePolicy.pointsFor('Absent', 15), 0);
    expect(AttendancePolicy.getPointsForStatus('Partial'), 5);
  });
}

extension on Timestamp {
  Timestamp plusMinutes(int minutes) =>
      Timestamp.fromDate(toDate().add(Duration(minutes: minutes)));
}
