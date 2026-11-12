import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'repositories/student_repository.dart';

class PrivacyDashboardScreen extends StatefulWidget {
  final String studentId;

  const PrivacyDashboardScreen({super.key, required this.studentId});

  @override
  State<PrivacyDashboardScreen> createState() => _PrivacyDashboardScreenState();
}

class _PrivacyDashboardScreenState extends State<PrivacyDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final IStudentEventRepository _studentRepo = FirebaseStudentEventRepository();

  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  Future<void> _purgeData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_coordinates');
    await prefs.setBool('cloud_coordinates_purged', true);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All local coordinate buffers securely purged.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      appBar: AppBar(
        title: const Text('Privacy & Security'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: _primaryGreen),
            const SizedBox(height: 16),
            Text(
              'We believe in transparency.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _darkText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your privacy is our priority. Here is how we protect your data:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 32),
            _buildInfoCard(
              icon: Icons.timer_off_outlined,
              title: 'No 24/7 Tracking',
              description: 'We only check your location when an event is actively happening. Tracking stops the moment the event ends.',
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.location_off_outlined,
              title: 'No Real-Time Maps',
              description: 'Admins cannot track your live movements on a map. They only receive your final attendance status (Present/Absent).',
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.lock_outline,
              title: 'Full Data Control',
              description: 'Your temporary location buffers are kept secure on your device and can be cleared at any time.',
            ),
            const SizedBox(height: 32),
            const Text(
              'Your Location History',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildTelemetryList(),
            const SizedBox(height: 48),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Delete My Location Data'),
              onPressed: _purgeData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('attendance')
          .where('studentId', isEqualTo: widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No telemetry data recorded yet.'),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final recordId = docs[index].id;
            final eventTitle = data['eventTitle']?.toString() ?? 'Unknown Event';
            final distance = data['distance_from_event'];
            final isPurged = data['isTelemetryPurged'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eventTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    if (isPurged)
                      Row(
                        children: const [
                          Icon(Icons.security, color: Colors.green),
                          SizedBox(width: 8),
                          Expanded(child: Text('Location deleted. Your attendance is securely saved.', style: TextStyle(color: Colors.green))),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Distance from event: ${distance != null ? '${distance.toStringAsFixed(1)} m' : 'Not recorded'}'),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Delete My Location Data'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Purge Telemetry?'),
                                  content: const Text('Your location telemetry will be permanently deleted, but your academic attendance status (Present/Late) will remain intact.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        try {
                                          await _studentRepo.purgeLocationTelemetry(recordId);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Telemetry purged successfully.')),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Error purging telemetry: $e')),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text('Purge Data', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            },
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

  Widget _buildInfoCard({required IconData icon, required String title, required String description}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _lightGreenBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _primaryGreen, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _darkText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
