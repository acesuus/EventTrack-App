import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart' as csv_pkg;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'attendance_policy.dart';
import 'widgets/export_events_dialog.dart';

class ExportUtils {
  static Future<void> showExportDialog(
    BuildContext context,
    Color primaryGreen,
  ) async {
    final pageContext = context;
    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore.collection('events').get();

    if (snapshot.docs.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No events found.')));
      return;
    }

    if (!context.mounted) return;
    final selection = await showDialog<ExportSelection>(
      context: context,
      builder: (_) => ExportEventsDialog(
        primaryColor: primaryGreen,
        events: snapshot.docs
            .map(
              (doc) => ExportEventOption(
                id: doc.id,
                title: doc.data()['title']?.toString() ?? 'Untitled event',
              ),
            )
            .toList(),
      ),
    );

    if (selection == null || !pageContext.mounted) return;
    switch (selection.format) {
      case ReportFormat.csv:
        await _generateAndShareCSV(pageContext, selection.eventIds);
      case ReportFormat.pdf:
        await _generateAndSharePDF(pageContext, selection.eventIds);
    }
  }

  static Future<void> _generateAndShareCSV(
    BuildContext context,
    List<String> selectedEventIds,
  ) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generating CSV...')));

    try {
      final firestore = FirebaseFirestore.instance;

      // Every student who has logged in has a profile in `users`.
      final studentsSnapshot = await firestore.collection('users').get();
      Map<String, Map<String, dynamic>> studentsMap = {};
      for (var doc in studentsSnapshot.docs) {
        studentsMap[doc.id] = doc.data();
      }

      List<List<dynamic>> csvData = [
        [
          'Event Name',
          'Student ID',
          'Student Name',
          'Program',
          'Year & Block',
          'Status',
          'Points',
          'Time In',
        ],
      ];

      for (String eventId in selectedEventIds) {
        final eventDoc = await firestore
            .collection('events')
            .doc(eventId)
            .get();
        final eventName = eventDoc.data()?['title'] ?? 'Event';

        final attendanceSnapshot = await firestore
            .collection('attendance')
            .where('eventId', isEqualTo: eventId)
            .get();

        Map<String, dynamic> eventAttendanceMap = {};
        for (var doc in attendanceSnapshot.docs) {
          final attData = doc.data();
          if (attData['studentId'] != null) {
            eventAttendanceMap[attData['studentId']] = attData;
          }
        }

        // Also include check-ins from students without a saved profile.
        final eventStudents = <String, Map<String, dynamic>>{
          ...studentsMap,
          for (final id in eventAttendanceMap.keys)
            if (!studentsMap.containsKey(id)) id: const <String, dynamic>{},
        };
        eventStudents.forEach((studentId, studentData) {
          String rawId = studentId.replaceAll('-', '');
          var attendanceRecord =
              eventAttendanceMap[studentId] ?? eventAttendanceMap[rawId];

          if (attendanceRecord != null) {
            String timeInStr = '';
            if (attendanceRecord['timeIn'] is Timestamp) {
              timeInStr = (attendanceRecord['timeIn'] as Timestamp)
                  .toDate()
                  .toIso8601String();
            }

            final status = attendanceRecord['status']?.toString() ?? 'Present';
            final pts =
                attendanceRecord['pointsAwarded'] ??
                AttendancePolicy.getPointsForStatus(status);

            csvData.add([
              eventName,
              studentId,
              studentData['name'] ?? '',
              studentData['program'] ?? '',
              studentData['yearBlock'] ?? '',
              status,
              pts,
              timeInStr,
            ]);
          } else {
            // Include absent students
            csvData.add([
              eventName,
              studentId,
              studentData['name'] ?? '',
              studentData['program'] ?? '',
              studentData['yearBlock'] ?? '',
              'Absent',
              0, // Absent gets 0 points
              '', // No time in
            ]);
          }
        });
      }

      String csvOutput = const csv_pkg.ListToCsvConverter().convert(csvData);

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/Attendance_Report_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csvOutput);

      await Share.shareXFiles([XFile(file.path)], text: 'Attendance Report');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating CSV: $e')));
      }
    }
  }

  static Future<void> _generateAndSharePDF(
    BuildContext context,
    List<String> selectedEventIds,
  ) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generating PDF...')));

    try {
      final firestore = FirebaseFirestore.instance;

      // Every student who has logged in has a profile in `users`.
      final studentsSnapshot = await firestore.collection('users').get();
      Map<String, Map<String, dynamic>> studentsMap = {};
      for (var doc in studentsSnapshot.docs) {
        studentsMap[doc.id] = doc.data();
      }

      final pdf = pw.Document();

      for (String eventId in selectedEventIds) {
        final eventDoc = await firestore
            .collection('events')
            .doc(eventId)
            .get();
        final eventName = eventDoc.data()?['title'] ?? 'Event';

        final attendanceSnapshot = await firestore
            .collection('attendance')
            .where('eventId', isEqualTo: eventId)
            .get();

        Map<String, dynamic> eventAttendanceMap = {};
        for (var doc in attendanceSnapshot.docs) {
          final attData = doc.data();
          if (attData['studentId'] != null) {
            eventAttendanceMap[attData['studentId']] = attData;
          }
        }

        List<List<String>> tableData = [
          [
            'Student ID',
            'Name',
            'Program',
            'Year/Block',
            'Status',
            'Points',
            'Time In',
          ],
        ];

        // Also include check-ins from students without a saved profile.
        final eventStudents = <String, Map<String, dynamic>>{
          ...studentsMap,
          for (final id in eventAttendanceMap.keys)
            if (!studentsMap.containsKey(id)) id: const <String, dynamic>{},
        };
        eventStudents.forEach((studentId, studentData) {
          String rawId = studentId.replaceAll('-', '');
          var attendanceRecord =
              eventAttendanceMap[studentId] ?? eventAttendanceMap[rawId];

          if (attendanceRecord != null) {
            String timeInStr = '';
            if (attendanceRecord['timeIn'] is Timestamp) {
              final date = (attendanceRecord['timeIn'] as Timestamp).toDate();
              timeInStr =
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
            }

            final status = attendanceRecord['status']?.toString() ?? 'Present';
            final pts =
                attendanceRecord['pointsAwarded'] ??
                AttendancePolicy.getPointsForStatus(status);

            tableData.add([
              studentId,
              studentData['name']?.toString() ?? '',
              studentData['program']?.toString() ?? '',
              studentData['yearBlock']?.toString() ?? '',
              status,
              pts.toString(),
              timeInStr,
            ]);
          } else {
            // Include absent students in PDF
            tableData.add([
              studentId,
              studentData['name']?.toString() ?? '',
              studentData['program']?.toString() ?? '',
              studentData['yearBlock']?.toString() ?? '',
              'Absent',
              '0',
              '',
            ]);
          }
        });

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    'Attendance Report: $eventName',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  context: context,
                  data: tableData,
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.green800,
                  ),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.all(5),
                ),
              ];
            },
          ),
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/Attendance_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Attendance Report (PDF)');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
      }
    }
  }
}
