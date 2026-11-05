import 'package:event_track/widgets/export_events_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const events = [
  ExportEventOption(id: 'one', title: 'TALONG NI BADANG'),
  ExportEventOption(id: 'two', title: 'TEST - Session Flow'),
  ExportEventOption(id: 'three', title: 'bancao-bancao'),
  ExportEventOption(id: 'four', title: 'vitug works'),
];

Widget host({ValueChanged<ExportSelection?>? onResult}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final result = await showDialog<ExportSelection>(
            context: context,
            builder: (_) => const ExportEventsDialog(
              events: events,
              primaryColor: Color(0xFF28A776),
            ),
          );
          onResult?.call(result);
        },
        child: const Text('Open'),
      ),
    ),
  ),
);

void main() {
  testWidgets('remains usable with large text and a long event list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ExportEventsDialog(
            events: List.generate(
              30,
              (i) => ExportEventOption(
                id: '$i',
                title: 'Annual student leadership and community event $i',
              ),
            ),
            primaryColor: const Color(0xFF28A776),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    expect(find.text('Export CSV'), findsOneWidget);
    expect(tester.getBottomRight(find.byType(FilledButton)).dy, lessThan(568));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'requires events and returns selected IDs with the chosen format',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ExportSelection? result;
      await tester.pumpWidget(host(onResult: (value) => result = value));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('TALONG NI BADANG'));
      await tester.pumpAndSettle();
      expect(find.text('1 event selected · PDF report'), findsOneWidget);
      await tester.ensureVisible(find.text('CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();
      expect(result?.eventIds, ['one']);
      expect(result?.format, ReportFormat.csv);
    },
  );

  testWidgets('select all, clear all, and close work on a compact screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('4 events selected · PDF report'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.getBottomRight(find.byType(FilledButton)).dy, lessThan(568));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportEventsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
