import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'create_event_screen.dart';
import 'attendance_monitoring_screen.dart';
import 'admin_settings_screen.dart';
class ManageEventsScreen extends StatefulWidget {
  const ManageEventsScreen({super.key});

  @override
  State<ManageEventsScreen> createState() => _ManageEventsScreenState();
}

class _ManageEventsScreenState extends State<ManageEventsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Theme Colors matching your UI
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "Unknown Date";
    return DateFormat('MMM dd, hh:mm a').format(timestamp.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      appBar: _buildAppBar(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('events').orderBy('startTime', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final events = snapshot.data?.docs ?? [];
          
          if (events.isEmpty) {
            return const Center(child: Text("No events found.", style: TextStyle(color: Colors.grey)));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: _primaryGreen, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Active Events (${events.length})', 
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Build the list of Event Cards
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      var eventDoc = events[index];
                      var data = eventDoc.data() as Map<String, dynamic>;
                      return _buildEventCard(eventDoc.id, data);
                    },
                  ),
                ],
              ),
            ),
          );
        },
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
      title: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('events').snapshots(),
        builder: (context, snapshot) {
          int count = snapshot.data?.docs.length ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Manage Events', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text('$count total events', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          );
        }
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0, top: 8, bottom: 8),
          child: InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateEventScreen()));
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add, color: _primaryGreen, size: 24),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(String eventId, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Green Calendar Icon Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_today, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              
              // Event Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['title'] ?? 'Untitled Event',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText),
                    ),
                    const SizedBox(height: 8),
                    _buildIconText(Icons.location_on_outlined, data['venueName'] ?? 'Unknown Venue'),
                    const SizedBox(height: 4),
                    _buildIconText(Icons.access_time, _formatDate(data['startTime'])),
                    const SizedBox(height: 4),
                    
                    // Live Attendee Counter using Firestore count()
                    FutureBuilder<AggregateQuerySnapshot>(
                      future: _firestore.collection('attendance').where('eventId', isEqualTo: eventId).count().get(),
                      builder: (context, snapshot) {
                        int attendeeCount = snapshot.data?.count ?? 0;
                        return _buildIconText(Icons.people_outline, '$attendeeCount attendees');
                      }
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                flex: 1,
                child: _buildActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  bgColor: _lightGreenBg,
                  textColor: _primaryGreen,
                  onTap: () {
                    // Navigate to the exact same screen, but pass the existing data!
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateEventScreen(
                          eventId: eventId,
                          existingData: data,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildActionButton(
                  icon: Icons.people_outline,
                  label: 'View Attendance',
                  bgColor: Colors.indigo.shade50,
                  textColor: Colors.indigo.shade600,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AttendanceMonitoringScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconText(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color bgColor, required Color textColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 1, // Focus on 'Events' tab
      selectedItemColor: _primaryGreen,
      unselectedItemColor: Colors.grey,
      onTap: (index) {
        if (index == 1) return; // Already on this tab
        if (index == 0) {
          Navigator.pop(context); // Go back to Dashboard
        } else if (index == 2) {
          Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => const AttendanceMonitoringScreen(), transitionDuration: Duration.zero));
        } else if (index == 3) {
          Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => const AdminSettingsScreen(), transitionDuration: Duration.zero));
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Events'),
        BottomNavigationBarItem(icon: Icon(Icons.insert_chart_outlined), label: 'Reports'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
    );
  }
}