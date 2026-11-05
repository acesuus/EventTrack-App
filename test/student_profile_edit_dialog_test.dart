import 'dart:async';

import 'package:event_track/widgets/student_profile_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Future<void> Function(String, String) save, {
  ValueChanged<bool?>? result,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final saved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => StudentProfileEditDialog(
              name: 'Kert',
              email: 'kert@psu.palawan.edu.ph',
              studentId: '202380358',
              onSave: save,
            ),
          );
          result?.call(saved);
        },
        child: const Text('Edit'),
      ),
    ),
  ),
);

Future<void> open(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invalid name and email show field errors without saving', (
    tester,
  ) async {
    var calls = 0;
    await open(tester, host((name, email) async => calls++));
    await tester.enterText(find.byKey(const Key('profile-name')), '  ');
    await tester.enterText(
      find.byKey(const Key('profile-email')),
      'invalid-email',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'waits for save, blocks duplicates, and returns trimmed updated details',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      String? savedName;
      String? savedEmail;
      bool? result;
      await open(
        tester,
        host((name, email) async {
          calls++;
          savedName = name;
          savedEmail = email;
          await pending.future;
        }, result: (value) => result = value),
      );
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        '  Kert Dela Cruz  ',
      );
      await tester.enterText(
        find.byKey(const Key('profile-email')),
        '  kert.updated@psu.palawan.edu.ph  ',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('profile-name')))
            .enabled,
        isFalse,
      );
      expect(result, isNull);
      pending.complete();
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(savedName, 'Kert Dela Cruz');
      expect(savedEmail, 'kert.updated@psu.palawan.edu.ph');
      expect(calls, 1);
      expect(find.byType(StudentProfileEditDialog), findsNothing);
    },
  );

  testWidgets('save failure retains edits and permits retry', (tester) async {
    var calls = 0;
    await open(
      tester,
      host((name, email) async {
        calls++;
        if (calls == 1) throw StateError('offline');
      }),
    );
    await tester.enterText(
      find.byKey(const Key('profile-name')),
      'Kert Updated',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not save your profile. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('profile-name')))
          .controller!
          .text,
      'Kert Updated',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(StudentProfileEditDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
