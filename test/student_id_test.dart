import 'package:event_track/student_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('student ID comes from the PSU email digits', () {
    expect(studentIdFromEmail('202312345@psu.palawan.edu.ph'), '2023-1-2345');
    expect(studentIdFromEmail(' 202312345@PSU.palawan.edu.ph '), '2023-1-2345');
    expect(studentIdFromEmail('20238035@psu.palawan.edu.ph'), isNull);
    expect(studentIdFromEmail('2023123451@psu.palawan.edu.ph'), isNull);
    expect(studentIdFromEmail('202312345@gmail.com'), isNull);
    expect(studentIdFromEmail('john@psu.palawan.edu.ph'), isNull);
  });

  test('admin-entered IDs and year & block are normalized', () {
    expect(normalizeStudentId('202312345'), '2023-1-2345');
    expect(normalizeStudentId(' 2023-1-2345 '), '2023-1-2345');
    expect(normalizeStudentId('2023-12-345'), '2023-1-2345');
    expect(normalizeStudentId('12345'), isNull);
    expect(normalizeYearBlock(' 1-a '), '1-A');
    expect(normalizeYearBlock('4-B2'), '4-B2');
    expect(normalizeYearBlock('5-A'), isNull);
    expect(normalizeYearBlock('1A'), isNull);
  });
}
