import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'create_event_screen.dart';
import 'attendance_monitoring_screen.dart';
import 'manage_events_screen.dart';
import 'admin_settings_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final int _selectedIndex = 0;

  // Theme Colors based on your UI
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "Unknown";
    return DateFormat('hh:mm a').format(timestamp.toDate());
  }

  Future<void> _deleteEvent(String docId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event?'),
        content: const Text('Are you sure you want to delete this event?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm && mounted) {
      await FirebaseFirestore.instance.collection('events').doc(docId).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildTopHeader(),
                  const SizedBox(height: 20),
                  _buildQuickActions(context),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            // The Real-Time Events List
            _buildActiveEventsSection(),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: _primaryGreen,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 0) return;
          if (index == 1) {
            Navigator.push(context, PageRouteBuilder(pageBuilder: (_, _, _) => const ManageEventsScreen(), transitionDuration: Duration.zero));
          } else if (index == 2) {
            Navigator.push(context, PageRouteBuilder(pageBuilder: (_, _, _) => const AttendanceMonitoringScreen(), transitionDuration: Duration.zero));
          } else if (index == 3) {
            Navigator.push(context, PageRouteBuilder(pageBuilder: (_, _, _) => const AdminSettingsScreen(), transitionDuration: Duration.zero));
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.insert_chart_outlined), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _primaryGreen,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Dashboard',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Welcome, Admin',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatCard(Icons.calendar_today, '1', 'Active Events'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildActionItem(
                title: 'Create Event',
                icon: Icons.add,
                isPrimary: true,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateEventScreen())),
              ),
              _buildActionItem(
                title: 'Monitor\nAttendance', 
                icon: Icons.people_outline, 
                isPrimary: false, 
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AttendanceMonitoringScreen()));
                }
              ),
              _buildActionItem(title: 'View Reports', icon: Icons.description_outlined, isPrimary: false, onTap: () {}),
             _buildActionItem(
                title: 'Manage Events', 
                icon: Icons.calendar_today_outlined, 
                isPrimary: false, 
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageEventsScreen()));
                }
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionItem({required String title, required IconData icon, required bool isPrimary, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPrimary ? _primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: _primaryGreen.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isPrimary ? Colors.white : _primaryGreen, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isPrimary ? Colors.white : _primaryGreen,
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveEventsSection() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
                TextButton(
                  onPressed: () {},
                  child: Text('View All', style: TextStyle(color: _primaryGreen)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Real-Time Firebase Listener
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('events').orderBy('startTime').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: Text("No active events currently.", style: TextStyle(color: Colors.grey))),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var eventDoc = snapshot.data!.docs[index];
                    var data = eventDoc.data() as Map<String, dynamic>;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primaryGreen,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.calendar_today, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['title'] ?? 'Untitled Event',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _deleteEvent(eventDoc.id),
                                      child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${data['venueName'] ?? 'Unknown Venue'} • 0 attendees",
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(_formatTime(data['startTime']), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle, size: 12, color: _primaryGreen),
                                          const SizedBox(width: 4),
                                          Text('Active', style: TextStyle(color: _primaryGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}