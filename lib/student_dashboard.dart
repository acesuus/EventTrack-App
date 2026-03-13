import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'event_tracking_screen.dart';
import 'student_login_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  final String studentId;
  final String studentName; // e.g., "Juan Dela Cruz"
  
  const StudentDashboardScreen({
    super.key, 
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Theme Colors
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  // Tracking State
  int _selectedIndex = 0;
  Timer? _locationTimer;

  @override
  void dispose() {
    _locationTimer?.cancel(); // PRIVACY: Stop timer when app closes
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const StudentLoginScreen()),
      (route) => false,
    );
  }

  // --- UI BUILDERS ---

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "--:--";
    return DateFormat('hh:mm a').format(timestamp.toDate());
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "Unknown Date";
    return DateFormat('EEEE, MMMM d, yyyy').format(timestamp.toDate());
  }

  Future<void> _joinEventWithOSPermission(String eventId, Map<String, dynamic> data) async {
    // 1. Trigger the default Android/iOS permission pop-up
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 2. If they hit "Deny", stop and show an error
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is strictly required to verify attendance.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 3. If they hit "Allow", jump straight to the tracking screen!
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventTrackingScreen( // Make sure this is imported at the top!
          studentId: widget.studentId,
          eventId: eventId,
          eventData: data,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildActiveEventsStream(),
                const SizedBox(height: 20),
                _buildQuickActions(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: BoxDecoration(
        color: _primaryGreen,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome Back!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(widget.studentName, style: const TextStyle(color: Colors.white, fontSize: 16)),
              Text('ID: ${widget.studentId}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white), onPressed: () {}),
              IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _handleLogout),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveEventsStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('events').orderBy('startTime').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No events currently.", style: TextStyle(color: Colors.grey)));
        }

        var events = snapshot.data!.docs;
        DateTime now = DateTime.now();

        List<DocumentSnapshot> activeEvents = [];
        List<DocumentSnapshot> upcomingEvents = [];

        for (var doc in events) {
          var data = doc.data() as Map<String, dynamic>;
          Timestamp? startTs = data['startTime'];
          Timestamp? endTs = data['endTime'];
          
          if (startTs == null || endTs == null) continue;
          
          DateTime startTime = startTs.toDate();
          DateTime endTime = endTs.toDate();

          if (endTime.isBefore(now)) {
            continue; // Past event
          } else if (startTime.isBefore(now) && endTime.isAfter(now)) {
            activeEvents.add(doc);
          } else if (startTime.isAfter(now)) {
            upcomingEvents.add(doc);
          }
        }

        if (activeEvents.isEmpty && upcomingEvents.isEmpty) {
          return const Center(child: Text("No upcoming or active events.", style: TextStyle(color: Colors.grey)));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeEvents.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('Active Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: activeEvents.length,
                itemBuilder: (context, index) {
                  var eventDoc = activeEvents[index];
                  var data = eventDoc.data() as Map<String, dynamic>;
                  return _buildEventCard(eventDoc.id, data, isActive: true);
                },
              ),
              const SizedBox(height: 10),
            ],
            if (upcomingEvents.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('Upcoming Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: upcomingEvents.length,
                itemBuilder: (context, index) {
                  var eventDoc = upcomingEvents[index];
                  var data = eventDoc.data() as Map<String, dynamic>;
                  return _buildEventCard(eventDoc.id, data, isActive: false);
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEventCard(String eventId, Map<String, dynamic> data, {required bool isActive}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive ? _lightGreenBg : Colors.orange.shade50, 
                  shape: BoxShape.circle
                ),
                child: Icon(
                  isActive ? Icons.sensors : Icons.schedule, 
                  color: isActive ? _primaryGreen : Colors.orange, 
                  size: 20
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? 'Active Event' : 'Upcoming Event', 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)
                  ),
                  Text(
                    isActive ? 'Live event available' : 'Starts soon', 
                    style: const TextStyle(fontSize: 12, color: Colors.grey)
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 20),

          // Event Details Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _lightGreenBg, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['title'] ?? 'Untitled Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
                const SizedBox(height: 12),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 18, color: _primaryGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['venueName'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, color: _darkText, fontSize: 14)),
                          Text(data['venueAddress'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 18, color: _primaryGreen),
                    const SizedBox(width: 8),
                    Text("${_formatTime(data['startTime'])} - ${_formatTime(data['endTime'])}", style: TextStyle(color: _darkText, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 18, color: _primaryGreen),
                    const SizedBox(width: 8),
                    Text(_formatDate(data['startTime']), style: TextStyle(color: _darkText, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Static Countdown Placeholder matching mockup
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFFFF9E6) : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isActive ? const Color(0xFFFFE082) : Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isActive ? Icons.timer_outlined : Icons.info_outline, size: 16, color: isActive ? const Color(0xFFD84315) : Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        isActive ? 'Check-in is open' : 'Wait for event start', 
                        style: TextStyle(color: _darkText, fontWeight: FontWeight.bold, fontSize: 12)
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isActive ? () => _joinEventWithOSPermission(eventId, data) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? _primaryGreen : Colors.grey.shade400,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: isActive ? 2 : 0,
              ),
              child: Text(
                isActive ? 'Join Event' : 'Not Yet Available', 
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
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
          Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.history, color: Colors.purple),
            ),
            title: Text('Attendance History', style: TextStyle(fontWeight: FontWeight.bold, color: _darkText)),
            subtitle: const Text('View past event records', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {},
          )
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      selectedItemColor: _primaryGreen,
      unselectedItemColor: Colors.grey,
      onTap: (index) => setState(() => _selectedIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
    );
  }
}