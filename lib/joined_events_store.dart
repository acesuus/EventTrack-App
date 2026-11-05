import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Event membership is separate from verified, points-bearing attendance.
class JoinedEventsStore extends ChangeNotifier {
  JoinedEventsStore({SharedPreferences? preferences})
    : _preferences = preferences;

  static final instance = JoinedEventsStore();
  SharedPreferences? _preferences;
  final Map<String, Set<String>> _joined = {};

  String _key(String studentId) => 'joined_events_$studentId';

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  bool contains(String studentId, String eventId) =>
      _joined[studentId]?.contains(eventId) ?? false;

  Future<void> load(String studentId) async {
    final prefs = await _prefs();
    final ids = {
      ...?prefs.getStringList(_key(studentId)),
      ...?_joined[studentId],
    };
    if (!setEquals(ids, _joined[studentId])) {
      _joined[studentId] = ids;
      notifyListeners();
    }
  }

  Future<void> join(String studentId, String eventId) async {
    final prefs = await _prefs();
    final ids = {
      ...?prefs.getStringList(_key(studentId)),
      ...?_joined[studentId],
      eventId,
    };
    if (!await prefs.setStringList(_key(studentId), ids.toList())) {
      throw StateError('Could not save joined event.');
    }
    if (!setEquals(ids, _joined[studentId])) {
      _joined[studentId] = ids;
      notifyListeners();
    }
  }
}
