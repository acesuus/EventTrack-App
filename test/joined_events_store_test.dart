import 'package:event_track/joined_events_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'joining outside the venue survives dashboard and store recreation',
    () async {
      final firstScreen = JoinedEventsStore();
      await firstScreen.join('student-1', 'event-1');
      firstScreen.dispose();

      final dashboard = JoinedEventsStore();
      await dashboard.load('student-1');
      expect(dashboard.contains('student-1', 'event-1'), isTrue);
      // Membership does not fabricate a verified attendance or offline check-in.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'joined_events_student-1'});
      dashboard.dispose();
    },
  );

  test('event selections are kept separate for each student', () async {
    final store = JoinedEventsStore();
    await store.join('student-1', 'event-1');
    await store.load('student-2');
    expect(store.contains('student-1', 'event-1'), isTrue);
    expect(store.contains('student-2', 'event-1'), isFalse);
    store.dispose();
  });

  test('resuming is idempotent and retains other joined events', () async {
    final store = JoinedEventsStore();
    var updates = 0;
    store.addListener(() => updates++);
    await store.join('student-1', 'event-1');
    await store.join('student-1', 'event-2');
    await store.join('student-1', 'event-1');
    expect(updates, 2);
    final restored = JoinedEventsStore();
    await restored.load('student-1');
    expect(restored.contains('student-1', 'event-1'), isTrue);
    expect(restored.contains('student-1', 'event-2'), isTrue);
    store.dispose();
    restored.dispose();
  });
}
