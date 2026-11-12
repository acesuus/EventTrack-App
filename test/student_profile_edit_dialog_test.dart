import 'dart:async';

import 'package:event_track/widgets/student_profile_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Future<void> Function(String, String, String) save, {
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
              program: 'BSCS',
              yearBlock: '3-A',
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
  testWidgets('school email shows the login email and is read-only', (
    tester,
  ) async {
    await open(tester, host((name, program, yearBlock) async {}));
    final field = find.byKey(const Key('profile-email'));
    expect(
      find.descendant(
        of: field,
        matching: find.text('kert@psu.palawan.edu.ph'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .readOnly,
      isTrue,
    );
  });

  testWidgets(
    'invalid name and year & block show field errors without saving',
    (tester) async {
      var calls = 0;
      await open(tester, host((name, program, yearBlock) async => calls++));
      await tester.enterText(find.byKey(const Key('profile-name')), '  ');
      await tester.enterText(find.byKey(const Key('profile-year-block')), '5A');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(
        find.text('Use year 1-4, a dash, then your block, e.g. 1-A.'),
        findsOneWidget,
      );
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'waits for save, blocks duplicates, and returns trimmed updated details',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      String? savedName;
      String? savedProgram;
      String? savedYearBlock;
      bool? result;
      await open(
        tester,
        host((name, program, yearBlock) async {
          calls++;
          savedName = name;
          savedProgram = program;
          savedYearBlock = yearBlock;
          await pending.future;
        }, result: (value) => result = value),
      );
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        '  Kert Dela Cruz  ',
      );
      await tester.enterText(
        find.byKey(const Key('profile-year-block')),
        ' 2-b ',
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
      expect(savedProgram, 'BSCS');
      expect(savedYearBlock, '2-B');
      expect(calls, 1);
      expect(find.byType(StudentProfileEditDialog), findsNothing);
    },
  );

  testWidgets('save failure retains edits and permits retry', (tester) async {
    var calls = 0;
    await open(
      tester,
      host((name, program, yearBlock) async {
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
