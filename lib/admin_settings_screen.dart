import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart' as csv_pkg;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import 'attendance_monitoring_screen.dart';
import 'export_utils.dart';
import 'manage_events_screen.dart';
import 'student_profile.dart';
import 'widgets/app_data_dialog.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  // Theme Colors
  final Color _primaryGreen = const Color(0xFF1E7F5A);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  // Toggle States

  /// Shows the required CSV column format before letting the admin pick a file.
  Future<void> _showImportInstructions() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDataDialog(
        title: 'Import Student List',
        icon: Icons.upload_file_outlined,
        subtitle: 'Prepare your CSV file before importing student records.',
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your CSV file must have these columns in this exact order:',
              ),
              const SizedBox(height: 12),
              Table(
                border: TableBorder.all(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(),
                },
                children: [
                  _instructionRow('Col', 'Field (Example)', isHeader: true),
                  _instructionRow('A', 'Student ID (0000-0-0000)'),
                  _instructionRow('B', 'Full Name (Juan D. Cruz)'),
                  _instructionRow('C', 'Program (BSCS)'),
                  _instructionRow('D', 'Year & Block (1-A)'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '• The first row is treated as a header and will be skipped.\n'
                '• Student ID may be written with or without dashes.\n'
                '• Year & Block must start with the year level (1-4), e.g. 3-B.\n'
                '• The list is optional: any student can still log in with their PSU email.\n'
                '• Rows with an invalid Student ID are skipped.\n'
                '• Existing students with the same ID will be updated.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose CSV File'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await _importStudentCSV();
    }
  }

  TableRow _instructionRow(String col, String field, {bool isHeader = false}) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
      color: _darkText,
    );
    return TableRow(
      decoration: isHeader
          ? BoxDecoration(color: _primaryGreen.withValues(alpha: 0.08))
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(col, style: style),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(field, style: style),
        ),
      ],
    );
  }

  Future<void> _importStudentCSV() async {
    fp.FilePickerResult? result = await fp.FilePicker.platform.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Importing students...')));

      try {
        final File file = File(result.files.single.path!);
        final String rawCsvString = await file.readAsString();
        final String safeCsvString = rawCsvString.replaceAll('\r\n', '\n');
        final List<List<dynamic>> csvTable = const csv_pkg.CsvToListConverter(
          eol: '\n',
        ).convert(safeCsvString);

        if (csvTable.length <= 1) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CSV is empty or only contains headers.'),
            ),
          );
          return;
        }

        final firestore = FirebaseFirestore.instance;
        WriteBatch batch = firestore.batch();
        int batchCount = 0;
        int totalImported = 0;
        int skipped = 0;

        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.isEmpty || row[0].toString().trim().isEmpty) continue;

          final finalId = normalizeStudentId(row[0].toString());
          if (finalId == null) {
            skipped++;
            continue;
          }
          final program = row.length > 2
              ? row[2].toString().trim().toUpperCase()
              : '';
          final yearBlock = row.length > 3
              ? normalizeYearBlock(row[3].toString())
              : null;

          final docRef = firestore.collection('students').doc(finalId);
          final data = {
            'studentId': finalId,
            'name': row.length > 1 ? row[1].toString().trim() : '',
            'program': studentPrograms.contains(program)
                ? program
                : defaultProgram,
            'yearBlock': yearBlock ?? '',
          };

          batch.set(docRef, data, SetOptions(merge: true));
          batchCount++;
          totalImported++;

          if (batchCount == 499) {
            await batch.commit();
            batch = firestore.batch();
            batchCount = 0;
          }
        }

        if (batchCount > 0) {
          await batch.commit();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                skipped == 0
                    ? 'Imported $totalImported students.'
                    : 'Imported $totalImported students. Skipped $skipped rows with an invalid Student ID.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error importing CSV: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildProfileCard(),
            const SizedBox(height: 20),
            _buildDataManagementCard(),
            const SizedBox(height: 24),
            _buildLogoutButton(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _primaryGreen,
      elevation: 0,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Admin preferences',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primaryGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FirebaseAuth.instance.currentUser?.displayName ??
                      'Administrator',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  FirebaseAuth.instance.currentUser?.email ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: _darkText.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Administrator',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _primaryGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddStudentDialog() async {
    final TextEditingController firstNameCtrl = TextEditingController();
    final TextEditingController miCtrl = TextEditingController();
    final TextEditingController lastNameCtrl = TextEditingController();
    final TextEditingController idCtrl = TextEditingController();
    String program = defaultProgram;
    String yearBlock = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AppDataDialog(
              title: 'Add Student Manually',
              icon: Icons.person_add_alt_1_outlined,
              subtitle: 'Optional. Students can also sign up on their own.',
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    TextFormField(
                      controller: firstNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                      ),
                    ),
                    TextFormField(
                      controller: miCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Middle Initial (Optional)',
                      ),
                    ),
                    TextFormField(
                      controller: lastNameCtrl,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                    ),
                    TextFormField(
                      controller: idCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Student ID (0000-0-0000)',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: program,
                      decoration: const InputDecoration(labelText: 'Program'),
                      items: [
                        for (final p in studentPrograms)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (val) => setState(() => program = val!),
                    ),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Year & Block (e.g., 1-A)',
                      ),
                      onChanged: (val) => yearBlock = val,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final finalId = normalizeStudentId(idCtrl.text);
                    final block = normalizeYearBlock(yearBlock);
                    if (finalId == null ||
                        firstNameCtrl.text.trim().isEmpty ||
                        lastNameCtrl.text.trim().isEmpty ||
                        block == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter a first and last name, a 9-digit Student ID, and a year & block like 1-A.',
                          ),
                        ),
                      );
                      return;
                    }

                    String fullName = [
                      firstNameCtrl.text.trim(),
                      miCtrl.text.trim(),
                      lastNameCtrl.text.trim(),
                    ].where((s) => s.isNotEmpty).join(' ');

                    try {
                      await FirebaseFirestore.instance
                          .collection('students')
                          .doc(finalId)
                          .set({
                            'studentId': finalId,
                            'name': fullName,
                            'program': program,
                            'yearBlock': block,
                          }, SetOptions(merge: true));
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Student added successfully.'),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditStudentDialog() async {
    final TextEditingController idCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AppDataDialog(
          title: 'Edit Student Details',
          icon: Icons.person_search_outlined,
          subtitle: 'Find a registered student by their Student ID.',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              TextFormField(
                controller: idCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Student ID'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final finalId = normalizeStudentId(idCtrl.text);
                if (finalId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter a 9-digit Student ID (0000-0-0000).',
                      ),
                    ),
                  );
                  return;
                }

                // Students who logged in have a profile; others may only be on the imported list.
                final firestore = FirebaseFirestore.instance;
                var collection = 'users';
                var doc = await firestore
                    .collection(collection)
                    .doc(finalId)
                    .get();
                if (!doc.exists) {
                  collection = 'students';
                  doc = await firestore
                      .collection(collection)
                      .doc(finalId)
                      .get();
                }
                if (!context.mounted) return;

                if (doc.exists) {
                  Navigator.pop(context); // Close the fetch dialog
                  _showUpdateStudentForm(finalId, doc.data()!, collection);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No student with this ID. They may not have logged in yet.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Fetch'),
            ),
          ],
        );
      },
    );
  }

  /// Lets a student register a new phone (e.g. after reinstalling the app).
  Future<void> _resetStudentDevice(
    BuildContext dialogContext,
    String studentId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Reset device?'),
        content: Text(
          '$studentId will be able to log in on a new phone. Their current phone will no longer be registered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset device'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(studentId);
      final deviceId =
          (await userRef.get()).data()?['registeredDeviceId']?.toString() ?? '';
      final batch = firestore.batch();
      if (deviceId.isNotEmpty) {
        batch.delete(firestore.collection('devices').doc(deviceId));
      }
      batch.set(userRef, {'registeredDeviceId': ''}, SetOptions(merge: true));
      await batch.commit();
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(
          content: Text('Device reset. The student can log in on a new phone.'),
        ),
      );
    } catch (e) {
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(
          content: Text("Couldn't reset the device. Check your connection."),
        ),
      );
    }
  }

  void _showUpdateStudentForm(
    String studentId,
    Map<String, dynamic> existingData,
    String collection,
  ) {
    final TextEditingController nameCtrl = TextEditingController(
      text: existingData['name'] ?? '',
    );
    String? program = existingData['program']?.toString();
    final TextEditingController yearBlockCtrl = TextEditingController(
      text: existingData['yearBlock'] ?? '',
    );
    if (!studentPrograms.contains(program)) program = defaultProgram;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AppDataDialog(
              title: 'Edit Student Details',
              icon: Icons.manage_accounts_outlined,
              subtitle: 'Update the profile of $studentId.',
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: program,
                      decoration: const InputDecoration(labelText: 'Program'),
                      items: [
                        for (final p in studentPrograms)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (val) => setState(() => program = val),
                    ),
                    TextFormField(
                      controller: yearBlockCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Year & Block (e.g., 1-A)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => _resetStudentDevice(context, studentId),
                  child: const Text('Reset device'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final yearBlock = normalizeYearBlock(yearBlockCtrl.text);
                    if (nameCtrl.text.trim().isEmpty ||
                        program == null ||
                        yearBlock == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter a name, choose a program, and a year & block like 1-A.',
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      await FirebaseFirestore.instance
                          .collection(collection)
                          .doc(studentId)
                          .update({
                            'name': nameCtrl.text.trim(),
                            'program': program,
                            'yearBlock': yearBlock,
                          });
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Student updated successfully.'),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDataManagementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data Management',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _darkText,
            ),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            label: 'Export Event Reports',
            textColor: _primaryGreen,
            bgColor: _primaryGreen.withValues(alpha: 0.1),
            borderColor: _primaryGreen.withValues(alpha: 0.3),
            onTap: () => ExportUtils.showExportDialog(context, _primaryGreen),
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            label: 'Import Student List',
            textColor: Colors.white,
            bgColor: _primaryGreen,
            borderColor: _primaryGreen,
            onTap: _showImportInstructions,
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            label: 'Add Student Manually',
            textColor: _primaryGreen,
            bgColor: _primaryGreen.withValues(alpha: 0.1),
            borderColor: _primaryGreen.withValues(alpha: 0.3),
            onTap: _showAddStudentDialog,
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            label: 'Edit Student Details',
            textColor: _primaryGreen,
            bgColor: Colors.white,
            borderColor: _primaryGreen,
            onTap: _showEditStudentDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color textColor,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: () async {
          final navigator = Navigator.of(context);
          await FirebaseAuth.instance.signOut();
          if (!context.mounted) return;
          navigator.popUntil((route) => route.isFirst);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: const Text(
          'Log Out',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 3, // Focus on 'Settings' tab
      selectedItemColor: _primaryGreen,
      unselectedItemColor: Color(0xFF616161),
      onTap: (index) {
        if (index == 3) return; // Already on this tab
        if (index == 0) {
          Navigator.popUntil(
            context,
            (route) => route.isFirst,
          ); // Dashboard is the root route
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, _, _) => const ManageEventsScreen(),
              transitionDuration: Duration.zero,
            ),
          );
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, _, _) => const AttendanceMonitoringScreen(),
              transitionDuration: Duration.zero,
            ),
          );
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today),
          label: 'Events',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.insert_chart_outlined),
          label: 'Reports',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
  }
}
