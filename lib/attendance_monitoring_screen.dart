import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'manage_events_screen.dart';
import 'admin_settings_screen.dart';
class AttendanceMonitoringScreen extends StatefulWidget {
  const AttendanceMonitoringScreen({super.key});

  @override
  State<AttendanceMonitoringScreen> createState() => _AttendanceMonitoringScreenState();
}

class _AttendanceMonitoringScreenState extends State<AttendanceMonitoringScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Theme Colors
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  // State Variables
  String? _selectedEventId;
  Map<String, dynamic>? _selectedEventData;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  final int _selectedIndex = 2; // "Attendance" tab

  Map<String, dynamic> rosterCache = {};
  bool _isLoadingRoster = true;

  // Pagination State
  int currentPage = 0;
  int itemsPerPage = 10;

  final List<String> _filters = ['All', 'Present', 'Late', 'Partial', 'Absent'];

  String formatAndGetLastName(String rawName) {
    List<String> parts = rawName.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return rawName;
    String lastName = parts.last;
    parts.removeLast();
    String firstAndMI = parts.join(' ');
    return '$lastName, $firstAndMI';
  }

  @override
  void initState() {
    super.initState();
    _fetchRoster();
  }

  Future<void> _fetchRoster() async {
    try {
      final snapshot = await _firestore.collection('students').get();
      final Map<String, dynamic> tempRoster = {};
      for (var doc in snapshot.docs) {
        tempRoster[doc.id] = doc.data();
      }
      if (mounted) {
        setState(() {
          rosterCache = tempRoster;
          _isLoadingRoster = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRoster = false;
        });
      }
    }
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "--:--";
    return DateFormat('hh:mm a').format(timestamp.toDate());
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "";
    return DateFormat('MMM dd, hh:mm a').format(timestamp.toDate());
  }

  // Helper to determine badge styling based on status
  Map<String, dynamic> _getStatusStyle(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return {'color': _primaryGreen, 'icon': Icons.check_circle_outline, 'bg': Colors.green.shade50};
      case 'late':
        return {'color': Colors.orange.shade700, 'icon': Icons.timer_outlined, 'bg': Colors.orange.shade50};
      case 'partial':
        return {'color': Colors.amber.shade700, 'icon': Icons.error_outline, 'bg': Colors.amber.shade50};
      case 'absent':
        return {'color': Colors.red.shade500, 'icon': Icons.cancel_outlined, 'bg': Colors.red.shade50};
      default:
        return {'color': Colors.grey, 'icon': Icons.help_outline, 'bg': Colors.grey.shade50};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _selectedEventId == null
                ? const Center(child: Text("Please select an event to monitor.", style: TextStyle(color: Colors.grey)))
                : _buildLiveDashboard(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      decoration: BoxDecoration(
        color: _primaryGreen,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Attendance Monitoring', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Real-time attendance tracking', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => setState(() {}), // Force refresh
              )
            ],
          ),
          const SizedBox(height: 20),
          
          // Event Dropdown Selector
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('events').orderBy('startTime', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
              
              var events = snapshot.data!.docs;
              
              // Auto-select first event if none is selected
              if (_selectedEventId == null && events.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() {
                    _selectedEventId = events.first.id;
                    _selectedEventData = events.first.data() as Map<String, dynamic>;
                  });
                });
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: _primaryGreen,
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    value: _selectedEventId,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    items: events.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(data['title'] ?? 'Unknown Event'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedEventId = value;
                        _selectedEventData = events.firstWhere((doc) => doc.id == value).data() as Map<String, dynamic>;
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveDashboard() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('attendance').where('eventId', isEqualTo: _selectedEventId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isLoadingRoster) {
          return const Center(child: CircularProgressIndicator());
        }

        // Explicitly type the list to prevent inference errors
        final List<QueryDocumentSnapshot> attendanceDocs = snapshot.data?.docs ?? [];

        // Combine attendance data with the global student roster
        List<Map<String, dynamic>> combinedList = [];
        
        for (var student in rosterCache.values) {
          String sId = student['studentId'] ?? '';
          
          var matchingDocs = attendanceDocs.where((d) {
            return (d.data() as Map<String, dynamic>)['studentId'] == sId;
          });

          if (matchingDocs.isNotEmpty) {
            var attendanceDoc = matchingDocs.first;
            var attData = attendanceDoc.data() as Map<String, dynamic>;
            attData['docId'] = attendanceDoc.id; // Store document ID inside map
            combinedList.add(attData);
          } else {
            combinedList.add({
              'studentId': sId,
              'status': 'Absent', // Default to absent if no check-in record exists
              'docId': '', // Empty means no attendance document yet
            });
          }
        }

        int total = combinedList.length;
        int present = combinedList.where((d) => d['status'] == 'Present').length;
        int late = combinedList.where((d) => d['status'] == 'Late').length;
        int partial = combinedList.where((d) => d['status'] == 'Partial').length;

        var filteredList = combinedList.where((data) {
          final status = data['status'] ?? 'Absent';
          final studentId = data['studentId']?.toString().toLowerCase() ?? '';
          
          bool matchesFilter = _selectedFilter == 'All' || status == _selectedFilter;
          bool matchesSearch = studentId.contains(_searchQuery.toLowerCase());
          
          return matchesFilter && matchesSearch;
        }).toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEventDetailsCard(),
                    const SizedBox(height: 16),
                    _buildStatsGrid(total, present, late, partial),
                    const SizedBox(height: 24),
                    _buildSearchAndFilter(),
                    const SizedBox(height: 24),
                    Text('Students (${filteredList.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final data = filteredList[index];
                  final String docId = data['docId'] as String;
                  
                  return _buildStudentCard(data, docId);
                },
                childCount: filteredList.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        );
      },
    );
  }

  Widget _buildEventDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_selectedEventData?['title'] ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(_selectedEventData?['venueName'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(_formatDate(_selectedEventData?['startTime']), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(int total, int present, int late, int partial) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        _buildStatCard('Total', total.toString(), Icons.people_outline, _darkText),
        _buildStatCard('Present', present.toString(), Icons.check_circle_outline, _primaryGreen),
        _buildStatCard('Late', late.toString(), Icons.timer_outlined, Colors.orange.shade700),
        _buildStatCard('Partial', partial.toString(), Icons.error_outline, Colors.amber.shade700),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _darkText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Column(
      children: [
        // Search Bar
        TextField(
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
              currentPage = 0;
            });
          },
          decoration: InputDecoration(
            hintText: 'Search by ID...',
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _filters.map((filter) {
              bool isSelected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  selectedColor: _primaryGreen,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onSelected: (selected) {
                    setState(() {
                      _selectedFilter = filter;
                      currentPage = 0;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        )
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> data, String docId) {
    String status = data['status'] ?? 'Unknown';
    var style = _getStatusStyle(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 20, right: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Student ${data['studentId']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _darkText)),
              const SizedBox(height: 4),
              Text('ID: ${data['studentId']}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                status == 'Partial' 
                    ? 'In: ${_formatTime(data['timeIn'])} • Out: ${_formatTime(data['timeOut'])}'
                    : 'In: ${_formatTime(data['timeIn'])}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
          
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: style['bg'],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: style['color'].withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(style['icon'], size: 14, color: style['color']),
                    const SizedBox(width: 4),
                    Text(status, style: TextStyle(color: style['color'], fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.how_to_reg, color: _primaryGreen),
                tooltip: 'Manual Override',
                onPressed: () => _showManualOverrideDialog(data, docId),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _showManualOverrideDialog(Map<String, dynamic> data, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Override'),
        content: Text('Force check-in for Student ${data['studentId']}? This bypasses GPS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        if (docId.isNotEmpty) {
          await _firestore.collection('attendance').doc(docId).update({
            'status': 'Present',
            'overrideBy': 'Admin',
            'timeIn': data['timeIn'] ?? FieldValue.serverTimestamp(),
          });
        } else {
          await _firestore.collection('attendance').add({
            'eventId': _selectedEventId,
            'studentId': data['studentId'],
            'status': 'Present',
            'overrideBy': 'Admin',
            'timeIn': FieldValue.serverTimestamp(),
          });
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student manually checked in.'), backgroundColor: Colors.green)
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to override: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      selectedItemColor: _primaryGreen,
      unselectedItemColor: Colors.grey,
      onTap: (index) {
        if (index == 2) return; // Already on this tab
        if (index == 0) {
          Navigator.pop(context); // Go back to Dashboard
        } else if (index == 1) {
          Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => const ManageEventsScreen(), transitionDuration: Duration.zero));
        } else if (index == 3) {
          Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => const AdminSettingsScreen(), transitionDuration: Duration.zero));
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Events'),
        BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Attendance'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
    );
  }
}