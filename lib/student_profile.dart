/// Shared rules for student IDs and profile fields.
library;

const studentPrograms = ['BSCS', 'BSIT'];

final _psuEmail = RegExp(r'^(\d{4})(\d)(\d{4})@psu\.palawan\.edu\.ph$');
final _yearBlock = RegExp(r'^[1-4]-[A-Z0-9]{1,3}$');

/// `202312345@psu.palawan.edu.ph` -> `2023-1-2345`, or null for any other email.
/// Must match `ownsStudent` in firestore.rules.
String? studentIdFromEmail(String email) {
  final m = _psuEmail.firstMatch(email.trim().toLowerCase());
  return m == null ? null : '${m[1]}-${m[2]}-${m[3]}';
}

/// `202312345` or `2023-1-2345` -> `2023-1-2345`, or null if it isn't 9 digits.
String? normalizeStudentId(String raw) => studentIdFromEmail(
  '${raw.replaceAll(RegExp(r'[\s-]'), '')}@psu.palawan.edu.ph',
);

/// Year level 1-4, a dash, then the block, e.g. `1-A`. Returns the uppercase form or null.
String? normalizeYearBlock(String raw) {
  final value = raw.trim().toUpperCase();
  return _yearBlock.hasMatch(value) ? value : null;
}
