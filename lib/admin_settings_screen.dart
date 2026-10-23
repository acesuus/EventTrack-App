import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart' as csv_pkg;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'attendance_monitoring_screen.dart';
import 'export_utils.dart';
import 'manage_events_screen.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  // Theme Colors
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  // Toggle States
  bool _notificationsEnabled = true;
  bool _autoBackupEnabled = true;

  /// Shows the required CSV column format before letting the admin pick a file.
  Future<void> _showImportInstructions() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            const Text('Import Instructions'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your CSV file must have these columns in this exact order:'),
              const SizedBox(height: 12),
              Table(
                border: TableBorder.all(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
                children: [
                  _instructionRow('Col', 'Field (Example)', isHeader: true),
                  _instructionRow('A', 'Student ID (2021-1-00123)'),
                  _instructionRow('B', 'Full Name (Juan D. Cruz)'),
                  _instructionRow('C', 'Program (BSCS, BSIT, BSIS)'),
                  _instructionRow('D', 'Year & Block (1-A)'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '• The first row is treated as a header and will be skipped.\n'
                '• Student ID may be written with or without dashes.\n'
                '• Year & Block must start with the year level (1-4), e.g. 3-B.\n'
                '• Existing students with the same ID will be updated.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
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
    final style = TextStyle(fontSize: 13, fontWeight: isHeader ? FontWeight.bold : FontWeight.normal, color: _darkText);
    return TableRow(
      decoration: isHeader ? BoxDecoration(color: Colors.blue.withValues(alpha: 0.08)) : null,
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(col, style: style)),
        Padding(padding: const EdgeInsets.all(8), child: Text(field, style: style)),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importing students...')));

      try {
        final File file = File(result.files.single.path!);
        final String rawCsvString = await file.readAsString();
        final String safeCsvString = rawCsvString.replaceAll('\r\n', '\n');
        final List<List<dynamic>> csvTable = const csv_pkg.CsvToListConverter(eol: '\n').convert(safeCsvString);

        if (csvTable.length <= 1) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV is empty or only contains headers.')));
          return;
        }

        final firestore = FirebaseFirestore.instance;
        WriteBatch batch = firestore.batch();
        int batchCount = 0;
        int totalImported = 0;

        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.isEmpty || row[0].toString().trim().isEmpty) continue;

          String rawId = row[0].toString().replaceAll('-', '').replaceAll(' ', '').trim();
          String finalId = rawId.length == 9 ? '${rawId.substring(0,4)}-${rawId.substring(4,5)}-${rawId.substring(5)}' : rawId;
          
          final docRef = firestore.collection('students').doc(finalId);
          final data = {
            'studentId': finalId,
            'name': row.length > 1 ? row[1].toString() : '',
            'program': row.length > 2 ? row[2].toString() : '',
            'yearBlock': row.length > 3 ? row[3].toString() : '',
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully imported $totalImported students!')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error importing CSV: $e')));
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
            _buildPreferencesCard(),
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
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text('Admin preferences', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
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
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jon Richmond Vitug', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
                const SizedBox(height: 4),
                Text('admin@psu.edu.ph', style: TextStyle(fontSize: 14, color: _darkText.withValues(alpha: 0.7))),
                const SizedBox(height: 4),
                Text('Administrator', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryGreen)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_outlined, color: _primaryGreen, size: 20),
              const SizedBox(width: 8),
              Text('Preferences', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
            ],
          ),
          const SizedBox(height: 16),
          _buildToggleRow(
            icon: Icons.notifications_none,
            title: 'Notifications',
            subtitle: 'Receive alerts for new attendance',
            value: _notificationsEnabled,
            onChanged: (val) => setState(() => _notificationsEnabled = val),
          ),
          const Divider(height: 24),
          _buildToggleRow(
            icon: Icons.storage_outlined,
            title: 'Auto-backup Reports',
            subtitle: 'Daily backup of attendance data',
            value: _autoBackupEnabled,
            onChanged: (val) => setState(() => _autoBackupEnabled = val),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({required IconData icon, required String title, required String subtitle, required bool value, required Function(bool) onChanged}) {
    return Row(
      children: [
        Icon(icon, color: _darkText.withValues(alpha: 0.6), size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkText)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: _primaryGreen,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Colors.grey.shade300,
        ),
      ],
    );
  }

  Future<void> _showAddStudentDialog() async {
    final TextEditingController firstNameCtrl = TextEditingController();
    final TextEditingController miCtrl = TextEditingController();
    final TextEditingController lastNameCtrl = TextEditingController();
    final TextEditingController idCtrl = TextEditingController();
    
    String program = 'BSCS';
    String yearBlock = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Student Manually'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: firstNameCtrl,
                      decoration: const InputDecoration(labelText: 'First Name'),
                    ),
                    TextFormField(
                      controller: miCtrl,
                      decoration: const InputDecoration(labelText: 'Middle Initial (Optional)'),
                    ),
                    TextFormField(
                      controller: lastNameCtrl,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                    ),
                    TextFormField(
                      controller: idCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Student ID'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: program,
                      decoration: const InputDecoration(labelText: 'Program'),
                      items: ['BSCS', 'BSIT', 'BSIS'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                      onChanged: (val) => setState(() => program = val!),
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Year & Block (e.g., 1-A)'),
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
                    String rawId = idCtrl.text.replaceAll('-', '').trim();
                    if (rawId.isEmpty || firstNameCtrl.text.isEmpty || lastNameCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill required fields.')));
                      return;
                    }
                    String finalId = rawId.length == 9 ? '${rawId.substring(0,4)}-${rawId.substring(4,5)}-${rawId.substring(5)}' : rawId;
                    
                    String fullName = [firstNameCtrl.text.trim(), miCtrl.text.trim(), lastNameCtrl.text.trim()]
                        .where((s) => s.isNotEmpty)
                        .join(' ');

                    try {
                      await FirebaseFirestore.instance.collection('students').doc(finalId).set({
                        'studentId': finalId,
                        'name': fullName,
                        'program': program,
                        'yearBlock': yearBlock,
                      });
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student added successfully.')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _showEditStudentDialog() async {
    final TextEditingController idCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Student Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the Student ID to fetch their details.'),
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
                String rawId = idCtrl.text.replaceAll('-', '').trim();
                if (rawId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a Student ID.')));
                  return;
                }
                String finalId = rawId.length == 9 ? '${rawId.substring(0,4)}-${rawId.substring(4,5)}-${rawId.substring(5)}' : rawId;
                
                final doc = await FirebaseFirestore.instance.collection('students').doc(finalId).get();
                if (!mounted) return;
                
                if (doc.exists) {
                  Navigator.pop(context); // Close the fetch dialog
                  _showUpdateStudentForm(finalId, doc.data() as Map<String, dynamic>);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student not found.')));
                }
              },
              child: const Text('Fetch'),
            ),
          ],
        );
      },
    );
  }

  void _showUpdateStudentForm(String studentId, Map<String, dynamic> existingData) {
    final TextEditingController nameCtrl = TextEditingController(text: existingData['name'] ?? '');
    String program = existingData['program'] ?? 'BSCS';
    final TextEditingController yearBlockCtrl = TextEditingController(text: existingData['yearBlock'] ?? '');

    if (!['BSCS', 'BSIT', 'BSIS'].contains(program)) {
      program = 'BSCS'; // Fallback
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Edit $studentId'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: program,
                      decoration: const InputDecoration(labelText: 'Program'),
                      items: ['BSCS', 'BSIT', 'BSIS'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                      onChanged: (val) => setState(() => program = val!),
                    ),
                    TextFormField(
                      controller: yearBlockCtrl,
                      decoration: const InputDecoration(labelText: 'Year & Block (e.g., 1-A)'),
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
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required.')));
                      return;
                    }
                    
                    try {
                      await FirebaseFirestore.instance.collection('students').doc(studentId).update({
                        'name': nameCtrl.text.trim(),
                        'program': program,
                        'yearBlock': yearBlockCtrl.text.trim(),
                      });
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student updated successfully.')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          }
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data Management', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
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
            textColor: Colors.blue.shade700,
            bgColor: Colors.blue.withValues(alpha: 0.1),
            borderColor: Colors.blue.withValues(alpha: 0.3),
            onTap: _showImportInstructions,
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            label: 'Add Student Manually',
            textColor: Colors.white,
            bgColor: _primaryGreen,
            borderColor: _primaryGreen,
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

  Widget _buildActionButton({required String label, required Color textColor, required Color bgColor, required Color borderColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
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
        onPressed: () {
          // Logic to sign out and return to login screen goes here
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: const Text('Log Out', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 3, // Focus on 'Settings' tab
      selectedItemColor: _primaryGreen,
      unselectedItemColor: Colors.grey,
      onTap: (index) {
        if (index == 3) return; // Already on this tab
        if (index == 0) {
          Navigator.pop(context); // Go back to Dashboard
        } else if (index == 1) {
          Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => const ManageEventsScreen(), transitionDuration: Duration.zero));
        } else if (index == 2) {
          Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => const AttendanceMonitoringScreen(), transitionDuration: Duration.zero));
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Events'),
        BottomNavigationBarItem(icon: Icon(Icons.insert_chart_outlined), label: 'Reports'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
  }
}