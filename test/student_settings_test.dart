import 'package:event_track/widgets/student_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host({
  required ValueChanged<String> onAction,
  double scale = 1,
  String email = 'student@psu.palawan.edu.ph',
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: StudentSettingsContent(
      name: 'Juan Dela Cruz',
      studentId: '2023-8-0358',
      email: email,
      hasConsented: true,
      deviceProtected: true,
      onEdit: () => onAction('edit'),
      onPrivacy: () => onAction('privacy'),
      onLocation: () => onAction('location'),
      onPermissions: () => onAction('permissions'),
      onLogout: () => onAction('logout'),
    ),
  ),
);

void main() {
  testWidgets('photo actions are accessible and disabled while updating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var changes = 0;
    Widget photoSettings(bool busy) => MaterialApp(
      home: Scaffold(
        body: StudentSettingsContent(
          name: 'Kert',
          studentId: '202380358',
          email: 'kert@psu.palawan.edu.ph',
          hasConsented: true,
          deviceProtected: true,
          photoBusy: busy,
          onEdit: () {},
          onPrivacy: () {},
          onLocation: () {},
          onPermissions: () {},
          onLogout: () {},
          onPhotoChange: () => changes++,
        ),
      ),
    );
    await tester.pumpWidget(photoSettings(false));
    await tester.tap(find.text('Add photo'));
    expect(changes, 1);
    await tester.pumpWidget(photoSettings(true));
    await tester.pump();
    expect(find.text('Updating photo…'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Updating photo…'),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile and grouped settings actions remain usable on a compact phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final actions = <String>[];
      await tester.pumpWidget(host(onAction: actions.add));
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.text('2023-8-0358'), findsOneWidget);
      for (final label in [
        'Edit profile',
        'Privacy notice',
        'Location settings',
        'App permissions',
        'Sign out',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(actions, ['edit', 'privacy', 'location', 'permissions', 'logout']);
    },
  );

  testWidgets(
    'long email wraps at large text sizes and absent email has a clear value',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          onAction: (_) {},
          scale: 2,
          email: 'juan.delacruz.student@psu.palawan.edu.ph',
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Edit profile'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(onAction: (_) {}, email: '202380358'));
      await tester.pumpAndSettle();
      expect(find.text('Not added'), findsOneWidget);
      expect(find.text('Program'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
