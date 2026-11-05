import 'package:event_track/widgets/student_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const details = StudentEventDetails(
  title: 'Happy Birthday Badang',
  venue: 'Gymnasium',
  time: '1:02 PM – 2:02 PM',
  date: 'Wednesday, November 4, 2026',
);

Widget host(Widget child, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  ),
);

void main() {
  testWidgets('active event action remains available on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var joined = false;
    await tester.pumpWidget(
      host(
        Column(
          children: [
            StudentEventCard(
              details: details,
              status: 'Check-in is open',
              statusDetail: 'Ends in 56 min',
              isActive: true,
              buttonLabel: 'Join Event',
              onJoin: () => joined = true,
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Join Event'));
    await tester.tap(find.text('Join Event'));
    expect(joined, isTrue);
  });

  testWidgets('upcoming and finalized events cannot be joined', (tester) async {
    for (final label in ['Not Yet Available', 'Attendance Recorded']) {
      await tester.pumpWidget(
        host(
          StudentEventCard(
            details: details,
            status: label,
            isActive: false,
            buttonLabel: label,
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'long event details and location instructions wrap with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              StudentEventCard(
                details: const StudentEventDetails(
                  title:
                      'Annual student leadership and community outreach program',
                  venue: 'Palawan State University Main Campus Gymnasium',
                  address: 'Puerto Princesa, Palawan',
                  time: '11:30 AM – 12:30 PM',
                  date: 'Wednesday, November 4, 2026',
                ),
                status: 'Check-in opens in 2h 15m',
                isActive: false,
                buttonLabel: 'Not Yet Available',
              ),
              const StudentSurface(
                child: StudentTrackingStatus(
                  title: 'Outside Event Area',
                  description:
                      'Go to the event venue, then verify your location to check in.',
                  icon: Icons.location_searching,
                  color: StudentUi.muted,
                ),
              ),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.ensureVisible(find.text('Outside Event Area'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
