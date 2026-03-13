import 'package:flutter/material.dart';
import 'manage_events_screen.dart';
import 'attendance_monitoring_screen.dart';
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
            label: 'Export All Data',
            textColor: _primaryGreen,
            bgColor: _primaryGreen.withValues(alpha: 0.1),
            borderColor: _primaryGreen.withValues(alpha: 0.3),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting data...')));
            },
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            label: 'Import Student List',
            textColor: Colors.blue.shade700,
            bgColor: Colors.blue.withValues(alpha: 0.1),
            borderColor: Colors.blue.withValues(alpha: 0.3),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening file picker...')));
            },
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