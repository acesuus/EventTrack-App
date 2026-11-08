import 'package:event_track/student_login_screen.dart';
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
}
