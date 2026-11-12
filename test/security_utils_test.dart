import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:event_track/utils/security_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final record = {
    'studentId': '2023-8-0358',
    'eventId': 'e1',
    'status': 'Late',
    'timeIn': Timestamp.fromMillisecondsSinceEpoch(1000),
    'timeOut': Timestamp.fromMillisecondsSinceEpoch(2000),
    'totalOutsideSeconds': 0,
    'pointsAwarded': 5,
  };

  test('a signed record is not flagged', () {
    expect(SecurityUtils.looksTampered(SecurityUtils.signed(record)), isFalse);
  });

  test('changing the status after signing is flagged', () {
    final edited = {...SecurityUtils.signed(record), 'status': 'Present'};
    expect(SecurityUtils.looksTampered(edited), isTrue);
  });

  test('unsigned, overridden and appealed records are not flagged', () {
    expect(SecurityUtils.looksTampered(record), isFalse);
    final signed = SecurityUtils.signed(record);
    expect(
      SecurityUtils.looksTampered({
        ...signed,
        'status': 'Present',
        'manualOverride': true,
      }),
      isFalse,
    );
    expect(
      SecurityUtils.looksTampered({
        ...signed,
        'status': 'Present',
        'appealStatus': 'approved',
      }),
      isFalse,
    );
  });
}
