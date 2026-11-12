import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'repositories/admin_repository.dart';
import 'repositories/admin_auth_repository.dart';

class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final IAdminEventRepository _adminRepo = FirebaseAdminEventRepository();
  final IAdminAuthRepository _authRepo = FirebaseAdminAuthRepository();
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  Future<void> _handleDeviceReset(String studentId, bool approve) async {
    try {
      await _authRepo.resolveDeviceReset(studentId, approve);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Device reset approved' : 'Device reset rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing request: $e')),
        );
      }
    }
  }

  Future<void> _handleAttendanceAppeal(String recordId, bool approve) async {
    try {
      await _adminRepo.resolveAttendanceAppeal(recordId, approve);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Appeal approved' : 'Appeal rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing appeal: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _lightGreenBg,
        appBar: AppBar(
          backgroundColor: _primaryGreen,
          foregroundColor: Colors.white,
          title: const Text('Pending Requests'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Device Resets'),
              Tab(text: 'Attendance Appeals'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDeviceResetsTab(),
            _buildAttendanceAppealsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceResetsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .where('deviceResetStatus', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No pending device reset requests.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final studentId = docs[index].id;
            final reason = data['deviceResetReason']?.toString() ?? 'No reason provided';
            final name = data['name']?.toString() ?? 'Unknown Student';

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Student: $name ($studentId)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _darkText)),
                    const SizedBox(height: 8),
                    Text('Reason: $reason'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _handleDeviceReset(studentId, false),
                          child: const Text('Reject', style: TextStyle(color: Colors.red)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _handleDeviceReset(studentId, true),
                          style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
                          child: const Text('Approve', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAttendanceAppealsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('attendance')
          .where('appealStatus', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No pending attendance appeals.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final recordId = docs[index].id;
            final studentId = data['studentId']?.toString() ?? 'Unknown';
            final eventTitle = data['eventTitle']?.toString() ?? 'Unknown Event';
            final originalStatus = data['status']?.toString() ?? 'Unknown';
            final reason = data['appealReason']?.toString() ?? 'No reason provided';

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eventTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _darkText)),
                    const SizedBox(height: 4),
                    Text('Student: $studentId'),
                    Text('Current Status: $originalStatus', style: const TextStyle(color: Colors.orange)),
                    const SizedBox(height: 8),
                    Text('Reason: $reason'),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Image viewing disabled in prototype')),
                        );
                      },
                      icon: const Icon(Icons.image),
                      label: const Text('View Attached Image'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _handleAttendanceAppeal(recordId, false),
                          child: const Text('Reject', style: TextStyle(color: Colors.red)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _handleAttendanceAppeal(recordId, true),
                          style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
                          child: const Text('Approve', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
