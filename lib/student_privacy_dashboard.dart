import 'package:flutter/material.dart';

class StudentPrivacyDashboardScreen extends StatelessWidget {
  const StudentPrivacyDashboardScreen({super.key});

  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      appBar: AppBar(
        title: const Text('Privacy Dashboard'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your Data, Protected by Design',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _darkText,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'We believe in transparency. Here is exactly how your data is used and protected when you use EventTrack.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _buildInfoCard(
            icon: Icons.location_on_outlined,
            title: 'Location Data Collection',
            description: 'GPS is only used locally during active events. Your exact coordinates are NEVER sent to or stored in the cloud. We only save your final attendance result (Present/Absent).',
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.gps_off_outlined,
            title: 'Background Tracking',
            description: 'Continuous background tracking is strictly disabled. The app only accesses your GPS sensor when the Event Tracking screen is visibly open.',
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.phonelink_lock_outlined,
            title: 'Device Binding',
            description: 'To prevent proxy attendance, your account is bound to your physical device. Rest assured, your device ID is securely hashed and cannot be used to track you elsewhere.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _lightGreenBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _primaryGreen, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
