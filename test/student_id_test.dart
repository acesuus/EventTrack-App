import 'package:event_track/student_login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('student ID comes from the PSU email digits', () {
    expect(studentIdFromEmail('202380358@psu.palawan.edu.ph'), '2023-8-0358');
    expect(studentIdFromEmail(' 202380358@PSU.palawan.edu.ph '), '2023-8-0358');
    expect(studentIdFromEmail('20238035@psu.palawan.edu.ph'), isNull);
    expect(studentIdFromEmail('2023803581@psu.palawan.edu.ph'), isNull);
    expect(studentIdFromEmail('202380358@gmail.com'), isNull);
    expect(studentIdFromEmail('john@psu.palawan.edu.ph'), isNull);
  });
}
