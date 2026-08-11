import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'attendance_policy.dart';
import 'event_tracking_screen.dart';
import 'geofencing_service.dart';
import 'student_consent_screen.dart';
import 'student_login_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  final String studentId;
  final String studentName;

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

  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  int _selectedIndex = 0;
  Timer? _clockRefreshTimer;
  bool _isSyncingAttendance = false;

  bool _isOfflineMode = false;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  Future<void> _syncOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    final queueStr = prefs.getString('offline_attendance_queue');
    if (queueStr == null || queueStr.isEmpty) {
      await prefs.remove('cached_today_events');
      return;
    }

    try {
      final List<dynamic> queue = jsonDecode(queueStr);
      for (final item in queue) {
        final data = Map<String, dynamic>.from(item);
        final String eventId = data['eventId'];
        final String eventName = data['eventName'];
        final String status = data['status'];
        final int pointsAwarded = data['pointsAwarded'];
        final String timestampStr = data['timestamp'];

        final docRef = _firestore.collection('attendance').doc('${widget.studentId}_$eventId');
        
        await docRef.set({
          'studentId': widget.studentId,
          'eventId': eventId,
          'eventName': eventName,
          'eventTitle': eventName,
          'status': status,
          'pointsAwarded': pointsAwarded,
          'timeIn': Timestamp.fromDate(DateTime.parse(timestampStr)),
        }, SetOptions(merge: true));
      }

      await prefs.remove('offline_attendance_queue');
      await prefs.remove('cached_today_events');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline records successfully synced.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync failed. Please check your internet connection and try again.')),
        );
        setState(() => _isOfflineMode = true);
      }
    }
  }

  Future<void> _toggleOfflineMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      try {
        final now = DateTime.now();
        final startOfDay = DateTime(now.year, now.month, now.day);
        final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

        final snapshot = await _firestore
            .collection('events')
            .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get(const GetOptions(source: Source.server));

        List<Map<String, dynamic>> sanitizedEvents = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          
          if (data['startTime'] is Timestamp) {
            data['startTime'] = (data['startTime'] as Timestamp).toDate().toIso8601String();
          }
          if (data['endTime'] is Timestamp) {
            data['endTime'] = (data['endTime'] as Timestamp).toDate().toIso8601String();
          }
          if (data['createdAt'] is Timestamp) {
            data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
          }
          
          if (data['polygonPoints'] is List) {
            final points = data['polygonPoints'] as List<dynamic>;
            final sanitizedPoints = points.map((p) {
              if (p is GeoPoint) {
                return {'lat': p.latitude, 'lng': p.longitude};
              }
              return p;
            }).toList();
            data['polygonPoints'] = sanitizedPoints;
          }

          sanitizedEvents.add(data);
        }

        await prefs.setString('cached_today_events', jsonEncode(sanitizedEvents));

      } catch (e) {
        debugPrint("Pre-load fetch failed: $e");
      }
      await _firestore.disableNetwork();
      setState(() => _isOfflineMode = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Data pre-loaded. App is now in Offline Mode."))
        );
      }
    } else {
      await _firestore.enableNetwork();
      await _syncOfflineData();
      setState(() => _isOfflineMode = false);
      if (mounted && !_isOfflineMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("App is Online. Attendance synced."))
        );
      }
    }
  }
  @override
  void initState() {
    super.initState();
    _syncStudentAttendanceLifecycle();
    _clockRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _syncStudentAttendanceLifecycle();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clockRefreshTimer?.cancel();
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

  DocumentReference<Map<String, dynamic>> _attendanceRefForEvent(
    String eventId,
  ) {
    return _firestore
        .collection('attendance')
        .doc('${widget.studentId}_$eventId');
  }

  Future<void> _syncStudentAttendanceLifecycle() async {
    if (_isSyncingAttendance) return;
    _isSyncingAttendance = true;
    var changedAnyRecord = false;

    try {
      final attendanceSnapshot = await _firestore
          .collection('attendance')
          .where('studentId', isEqualTo: widget.studentId)
          .get();

      final now = DateTime.now();

      for (final attendanceDoc in attendanceSnapshot.docs) {
        final attendanceData = attendanceDoc.data();
        final eventId = attendanceData['eventId']?.toString();
        if (eventId == null || eventId.isEmpty) {
          continue;
        }

        final eventDoc = await _firestore
            .collection('events')
            .doc(eventId)
            .get();
        final eventData = eventDoc.data();
        if (!eventDoc.exists || eventData == null) {
          continue;
        }

        final changed = await _normalizeAttendanceRecord(
          attendanceRef: attendanceDoc.reference,
          attendanceData: attendanceData,
          eventData: eventData,
          now: now,
        );
        changedAnyRecord = changedAnyRecord || changed;
      }
    } catch (e) {
      debugPrint('Error syncing student attendance lifecycle: $e');
    } finally {
      _isSyncingAttendance = false;
      if (changedAnyRecord && mounted) {
        setState(() {});
      }
    }
  }

  Future<bool> _normalizeAttendanceRecord({
    required DocumentReference<Map<String, dynamic>> attendanceRef,
    required Map<String, dynamic> attendanceData,
    required Map<String, dynamic> eventData,
    required DateTime now,
  }) async {
    var record = AttendanceSessionRecord.fromFirestore(attendanceData);
    var changed = false;

    final fallbackStart =
        attendanceData['timeIn'] as Timestamp? ??
        eventData['startTime'] as Timestamp? ??
        Timestamp.now();

    if (record.needsLegacyBootstrap) {
      record = record.bootstrapLegacyIfNeeded(fallbackStart: fallbackStart);
      changed = true;
    }

    final eventEnd = eventData['endTime'] as Timestamp?;
    if (eventEnd != null &&
        AttendancePolicy.shouldAutoFinalize(
          timeOut: record.timeOut,
          eventEnd: eventEnd.toDate(),
          now: now,
        )) {
      record = record.finalize(eventEnd);
      changed = true;
    }

    if (!changed) {
      return false;
    }

    // FIX APPLIED HERE: Removed 'await' to allow offline fire-and-forget
    attendanceRef.set(
      record.toFirestoreFields(
        studentId: widget.studentId,
        eventId: attendanceData['eventId']?.toString() ?? '',
        eventTitle:
            attendanceData['eventTitle']?.toString() ??
            eventData['title']?.toString() ??
            'Event',
      ),
      SetOptions(merge: true),
    );

    return true;
  }

  Future<String> _getHardwareFingerprint() async {
    if (kIsWeb) return 'web_browser_device';
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios_id';
    }
    throw UnsupportedError('Unsupported platform for device binding');
  }

  Future<void> _enforceDeviceBinding(String studentId) async {
    final fingerprint = await _getHardwareFingerprint();
    final userDocRef = _firestore.collection('users').doc(studentId);
    final prefs = await SharedPreferences.getInstance();

    // 1. LOCAL BINDING (Anti-Clear Data protection for Offline Mode)
    final localBoundId = prefs.getString('bound_student_id');
    if (localBoundId != null && localBoundId != studentId) {
      throw Exception('SECURITY_VIOLATION: This phone is permanently bound to Student ID: $localBoundId. Multiple accounts on one device are prohibited.');
    }

    // 2. CLOUD BINDING (Cross-references Firestore to stop 1-device-to-many-accounts)
    DocumentSnapshot<Map<String, dynamic>>? userDoc;
    try {
      userDoc = await userDocRef.get(GetOptions(source: _isOfflineMode ? Source.cache : Source.serverAndCache));
    } catch (e) {
      if (_isOfflineMode) return; // Rely on the localBoundId check above if offline
      rethrow;
    }

    // Helper function to claim the device in the cloud
    Future<void> claimDevice() async {
      if (_isOfflineMode) return; // Cannot claim a new device while offline
      
      // Cloud Gatekeeper: Check if this physical phone is already owned by someone else!
      final deviceCheck = await _firestore.collection('users')
          .where('registeredDeviceId', isEqualTo: fingerprint)
          .get(const GetOptions(source: Source.server));

      if (deviceCheck.docs.isNotEmpty) {
        final ownerId = deviceCheck.docs.first.id;
        if (ownerId != studentId) {
          throw Exception('SECURITY_VIOLATION: This physical phone is already permanently bound to Student ID: $ownerId. Proxy attendance is strictly prohibited.');
        }
      }
      
      // If clear, claim the device in the cloud and locally
      await userDocRef.set({'registeredDeviceId': fingerprint}, SetOptions(merge: true));
      await prefs.setString('bound_student_id', studentId);
    }

    if (!userDoc.exists) {
      await claimDevice();
      return;
    }

    final userData = userDoc.data()!;
    final cloudDeviceId = userData['registeredDeviceId'];

    if (cloudDeviceId == null || cloudDeviceId.toString().isEmpty) {
      await claimDevice();
    } else if (cloudDeviceId != fingerprint) {
      throw Exception('SECURITY_VIOLATION: Identity mismatch. Your account is bound to a different physical device.');
    } else {
      // Success: Re-sync local storage in case they managed to clear app data but still passed the cloud check
      await prefs.setString('bound_student_id', studentId);
    }
  }

  Future<void> _joinEventWithOSPermission(
    String eventId,
    Map<String, dynamic> data,
  ) async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission is required to verify attendance.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Location permission is permanently denied. Please enable it in settings.',
          ),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Settings',
            textColor: Colors.white,
            onPressed: () {
              Geolocator.openAppSettings();
            },
          ),
        ),
      );
      return;
    }

    final attendanceRef = _attendanceRefForEvent(eventId);
    DocumentSnapshot<Map<String, dynamic>>? existingAttendance;

    try {
      existingAttendance = await attendanceRef.get(GetOptions(source: _isOfflineMode ? Source.cache : Source.serverAndCache));
    } catch (e) {
      existingAttendance = null;
    }

    if (existingAttendance != null && existingAttendance.exists) {
      final attendanceData = existingAttendance.data() ?? <String, dynamic>{};
      await _normalizeAttendanceRecord(
        attendanceRef: attendanceRef,
        attendanceData: attendanceData,
        eventData: data,
        now: DateTime.now(),
      );
      final refreshedAttendance = await attendanceRef.get(GetOptions(source: _isOfflineMode ? Source.cache : Source.serverAndCache));
      final refreshedData = refreshedAttendance.data() ?? attendanceData;
      final existingRecord = AttendanceSessionRecord.fromFirestore(
        refreshedData,
      );

      if (!AttendancePolicy.canJoinExistingAttendance(existingRecord.timeOut)) {
        if (!mounted) return;
        final finalStatus = _displayAttendanceStatus(existingRecord.status);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attendance already finalized as $finalStatus for this event.',
            ),
            backgroundColor: _darkText,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Verifying your device and location...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await _enforceDeviceBinding(widget.studentId);
      // Fetch current position to ensure the GPS sensor is active
      await Geolocator.getCurrentPosition();
    } catch (e) {
      if (!mounted) return;
      
      final errorMessage = e.toString();
      final displayMessage = errorMessage.contains('SECURITY_VIOLATION') 
          ? errorMessage.replaceAll('Exception: ', '') 
          : 'Failed to verify location. Please ensure GPS is enabled.';
          
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(displayMessage)),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventTrackingScreen(
          studentId: widget.studentId,
          eventId: eventId,
          eventData: data,
        ),
      ),
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '--:--';
    return DateFormat('hh:mm a').format(timestamp.toDate());
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown Date';
    return DateFormat('EEEE, MMMM d, yyyy').format(timestamp.toDate());
  }

  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Not recorded';
    return DateFormat('MMM d, yyyy - hh:mm a').format(timestamp.toDate());
  }

  String _formatReturnCountFromRecord(Map<String, dynamic> data) {
    final rawSessions = data['sessions'] as List<dynamic>?;
    final sessionCount = rawSessions?.length ?? 0;
    final returnCount = sessionCount <= 1 ? 0 : sessionCount - 1;
    if (returnCount == 0) return 'No returns';
    if (returnCount == 1) return '1 return';
    return '$returnCount returns';
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes == 0) {
      return '${remainingSeconds}s';
    }
    return '${minutes}m ${remainingSeconds}s';
  }

  String _relativeTimeLabel(DateTime now, DateTime target) {
    final difference = target.difference(now);

    if (difference.inMinutes.abs() < 1) {
      return 'now';
    }

    if (difference.isNegative) {
      final elapsed = now.difference(target);
      if (elapsed.inHours >= 1) {
        return '${elapsed.inHours}h ${elapsed.inMinutes.remainder(60)}m ago';
      }
      return '${elapsed.inMinutes} min ago';
    }

    if (difference.inHours >= 1) {
      return 'in ${difference.inHours}h ${difference.inMinutes.remainder(60)}m';
    }

    return 'in ${difference.inMinutes} min';
  }

  Map<String, dynamic> _getEventWindowInfo(
    Map<String, dynamic> data,
    DateTime now,
  ) {
    final startTs = data['startTime'] as Timestamp?;
    final endTs = data['endTime'] as Timestamp?;

    if (startTs == null || endTs == null) {
      return {
        'phase': 'invalid',
        'isActive': false,
        'bannerText': 'Event schedule missing',
        'bannerColor': Colors.grey.shade600,
        'bannerBg': Colors.grey.shade100,
        'buttonLabel': 'Unavailable',
      };
    }

    final startTime = startTs.toDate();
    final endTime = endTs.toDate();
    final earlyWindowMinutes =
        (data['checkInOpenMinutesBeforeStart'] as num?)?.toInt() ?? 15;
    final checkInOpenTime = startTime.subtract(
      Duration(minutes: earlyWindowMinutes),
    );

    if (endTime.isBefore(now)) {
      return {
        'phase': 'past',
        'isActive': false,
        'bannerText': 'Event ended ${_relativeTimeLabel(now, endTime)}',
        'bannerColor': Colors.grey.shade700,
        'bannerBg': Colors.grey.shade100,
        'buttonLabel': 'Closed',
      };
    }

    if (!checkInOpenTime.isAfter(now) && !endTime.isBefore(now)) {
      return {
        'phase': 'active',
        'isActive': true,
        'bannerText': 'Check-in is open',
        'bannerSubtext': 'Ends ${_relativeTimeLabel(now, endTime)}',
        'bannerColor': const Color(0xFFD84315),
        'bannerBg': const Color(0xFFFFF9E6),
        'buttonLabel': 'Join Event',
      };
    }

    return {
      'phase': 'upcoming',
      'isActive': false,
      'bannerText':
          'Check-in opens ${_relativeTimeLabel(now, checkInOpenTime)}',
      'bannerSubtext': 'Event starts ${_relativeTimeLabel(now, startTime)}',
      'bannerColor': Colors.blue.shade700,
      'bannerBg': Colors.blue.shade50,
      'buttonLabel': 'Not Yet Available',
    };
  }

  Map<String, dynamic> _getAttendanceStatusStyle(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return {
          'color': _primaryGreen,
          'bg': Colors.green.shade50,
          'icon': Icons.check_circle_outline,
        };
      case 'late':
        return {
          'color': Colors.orange.shade700,
          'bg': Colors.orange.shade50,
          'icon': Icons.timer_outlined,
        };
      case 'partial':
        return {
          'color': Colors.amber.shade700,
          'bg': Colors.amber.shade50,
          'icon': Icons.error_outline,
        };
      default:
        return {
          'color': Colors.grey.shade700,
          'bg': Colors.grey.shade100,
          'icon': Icons.help_outline,
        };
    }
  }

  String _displayAttendanceStatus(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return 'On Time';
      case 'late':
        return 'Late Check-In';
      case 'partial':
        return 'Partial Attendance';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      body: SafeArea(child: _buildSelectedTab()),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildSelectedTab() {
    switch (_selectedIndex) {
      case 1:
        return _buildCalendarTab();
      case 2:
        return _buildHistoryTab();
      case 3:
        return _buildSettingsTab();
      case 0:
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildCalendarTab() {
    return Column(
      children: [
        _buildPageHeader(
          title: 'Event Calendar',
          subtitle: 'Browse scheduled events by date',
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('events').orderBy('startTime').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final allEvents = snapshot.hasData ? snapshot.data!.docs : [];

              final filteredEvents = allEvents.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                if (data['startTime'] == null) return false;
                DateTime eventDate = (data['startTime'] as Timestamp).toDate();
                return isSameDay(eventDate, _selectedDay);
              }).toList();

              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TableCalendar(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                      calendarFormat: CalendarFormat.month,
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'Month',
                      },
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      calendarStyle: CalendarStyle(
                        selectedDecoration: BoxDecoration(
                          color: _primaryGreen,
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: _primaryGreen.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        markerDecoration: BoxDecoration(
                          color: _primaryGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        leftChevronVisible: true,
                        rightChevronVisible: true,
                      ),
                      eventLoader: (day) {
                        return allEvents.where((doc) {
                          var data = doc.data() as Map<String, dynamic>;
                          if (data['startTime'] == null) return false;
                          DateTime eventDate = (data['startTime'] as Timestamp).toDate();
                          return isSameDay(eventDate, day);
                        }).toList();
                      },
                    ),
                  ),
                  Expanded(
                    child: filteredEvents.isEmpty
                        ? const Center(
                            child: Text(
                              'No events scheduled for this date.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filteredEvents.length,
                            itemBuilder: (context, index) {
                              final doc = filteredEvents[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final windowInfo = _getEventWindowInfo(data, DateTime.now());
                              return _buildEventCard(
                                doc.id,
                                data,
                                windowInfo,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _buildHomeHeader(),
              const SizedBox(height: 20),
              _buildPointsCard(),
              const SizedBox(height: 20),
              _buildEventsSection(),
              const SizedBox(height: 20),
              _buildQuickActions(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPointsCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('attendance')
          .where('studentId', isEqualTo: widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        int totalPoints = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status']?.toString() ?? 'Absent';
            final pts = data['pointsAwarded'] ?? AttendancePolicy.getPointsForStatus(status);
            totalPoints += (pts as num).toInt();
          }
        }
        
        return InkWell(
          onTap: () => setState(() { _selectedIndex = 2; }),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primaryGreen, Colors.green.shade700],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _primaryGreen.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.stars, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CS Association Points',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalPoints pts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap to view breakdown ->',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        _buildPageHeader(
          title: 'Event Attendance & Points Ledger',
          subtitle: 'Review your past event check-ins and points earned',
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('attendance')
                .where('studentId', isEqualTo: widget.studentId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.history,
                  title: 'No attendance records yet',
                  subtitle: 'Your finished event attendance will appear here.',
                );
              }

              final records = snapshot.data!.docs.toList();
              records.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = (aData['timeIn'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                final bTime = (bData['timeIn'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                return bTime.compareTo(aTime);
              });

              int totalPoints = 0;
              for (var doc in records) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status']?.toString() ?? 'Absent';
                final pts = data['pointsAwarded'] ?? AttendancePolicy.getPointsForStatus(status);
                totalPoints += (pts as num).toInt();
              }

              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(20),
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
                        const Text(
                          'Total Points to Date',
                          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$totalPoints pts',
                          style: TextStyle(
                            color: _primaryGreen,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width > 600 ? MediaQuery.of(context).size.width : 600,
                        child: PaginatedDataTable(
                          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                          dataRowMaxHeight: 60,
                          columns: const [
                            DataColumn(label: Text('Event Name', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Event Type', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Remarks', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Points', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                          ],
                          source: _AttendanceDataSource(records),
                          rowsPerPage: 5,
                          availableRowsPerPage: const [5],
                          showFirstLastButtons: true,
                          columnSpacing: 20.0,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    return Column(
      children: [
        _buildPageHeader(
          title: 'Settings',
          subtitle: 'Manage your account, privacy, and app access',
        ),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: _firestore
                .collection('users')
                .doc(widget.studentId)
                .snapshots(),
            builder: (context, snapshot) {
              final userData =
                  snapshot.data?.data() as Map<String, dynamic>? ??
                  <String, dynamic>{};
              final hasConsented = userData['hasConsented'] == true;
              final deviceId =
                  userData['registeredDeviceId']?.toString() ??
                  'Not registered';
              final email = userData['email']?.toString() ?? 'No email saved';
              final deviceProtected =
                  deviceId.isNotEmpty && deviceId != 'Not registered';

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                children: [
                  _buildSettingsCard(
                    title: 'Student Account',
                    icon: Icons.person_outline,
                    children: [
                      _buildSettingsRow('Name', widget.studentName),
                      _buildSettingsRow('Student ID', widget.studentId),
                      _buildSettingsRow('School Email', email),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSettingsCard(
                    title: 'Privacy and Permissions',
                    icon: Icons.privacy_tip_outlined,
                    children: [
                      _buildSettingsRow(
                        'Privacy Notice',
                        hasConsented ? 'Accepted' : 'Needs review',
                      ),
                      _buildSettingsRow(
                        'Attendance Protection',
                        deviceProtected
                            ? 'This account is linked to your current device'
                            : 'Device protection is not set yet',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildActionTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Review Privacy Notice',
                    subtitle:
                        'Read the notice again and update your consent if needed',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StudentConsentScreen(
                            studentId: widget.studentId,
                            studentName: widget.studentName,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildActionTile(
                    icon: Icons.location_searching_outlined,
                    title: 'Turn On Location',
                    subtitle:
                        'Open your phone location settings if attendance cannot verify where you are',
                    onTap: () {
                      Geolocator.openLocationSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildActionTile(
                    icon: Icons.phone_android_outlined,
                    title: 'Open App Permissions',
                    subtitle:
                        'Manage location access and other permissions for EventTrack',
                    onTap: () {
                      Geolocator.openAppSettings();
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade500,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
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
              const Text(
                'Welcome Back!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.studentName,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              Text(
                'ID: ${widget.studentId}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _isOfflineMode ? Icons.cloud_off : Icons.cloud_done,
                  color: _isOfflineMode ? Colors.orange.shade300 : Colors.white,
                ),
                onPressed: () => _toggleOfflineMode(!_isOfflineMode),
                tooltip: _isOfflineMode ? 'Go Online' : 'Go Offline',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                onPressed: () => setState(() => _selectedIndex = 3),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: _handleLogout,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader({required String title, required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('events').orderBy('startTime').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final allEvents = snapshot.hasData ? snapshot.data!.docs : [];

        if (allEvents.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'No active events at PSU Main Campus',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final now = DateTime.now();
        final activeEvents = <Map<String, dynamic>>[];
        final upcomingEvents = <Map<String, dynamic>>[];

        for (final doc in allEvents) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['startTime'] == null) continue;
          
          final windowInfo = _getEventWindowInfo(data, now);
          final phase = windowInfo['phase'];

          if (phase == 'active') {
            activeEvents.add({
              'id': doc.id,
              'data': data,
              'windowInfo': windowInfo,
            });
          } else if (phase == 'upcoming') {
            upcomingEvents.add({
              'id': doc.id,
              'data': data,
              'windowInfo': windowInfo,
            });
          }
        }

        if (activeEvents.isEmpty && upcomingEvents.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'No upcoming or active events.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeEvents.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Active Events',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: activeEvents.length,
                itemBuilder: (context, index) {
                  final event = activeEvents[index];
                  return _buildEventCard(
                    event['id'] as String,
                    event['data'] as Map<String, dynamic>,
                    event['windowInfo'] as Map<String, dynamic>,
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            if (upcomingEvents.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Upcoming Events',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: upcomingEvents.length,
                itemBuilder: (context, index) {
                  final event = upcomingEvents[index];
                  return _buildEventCard(
                    event['id'] as String,
                    event['data'] as Map<String, dynamic>,
                    event['windowInfo'] as Map<String, dynamic>,
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEventCard(
    String eventId,
    Map<String, dynamic> data,
    Map<String, dynamic> windowInfo,
  ) {
    final isActive = windowInfo['isActive'] == true;
    final bannerColor = windowInfo['bannerColor'] as Color;
    final bannerBg = windowInfo['bannerBg'] as Color;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _attendanceRefForEvent(eventId).snapshots(),
      builder: (context, snapshot) {
        AttendanceSessionRecord? attendanceRecord;
        final attendanceData = snapshot.data?.data();
        if (attendanceData != null) {
          attendanceRecord = AttendanceSessionRecord.fromFirestore(
            attendanceData,
          );
          if (attendanceRecord.needsLegacyBootstrap) {
            final fallbackStart =
                attendanceData['timeIn'] as Timestamp? ??
                data['startTime'] as Timestamp? ??
                Timestamp.now();
            attendanceRecord = attendanceRecord.bootstrapLegacyIfNeeded(
              fallbackStart: fallbackStart,
            );
          }
        }

        final hasActiveAttendance =
            attendanceRecord != null && !attendanceRecord.isFinalized;
        final hasFinalizedAttendance = attendanceRecord?.isFinalized == true;
        final summaryStatus = attendanceRecord?.currentSummaryStatus;
        final buttonLabel = !isActive
            ? windowInfo['buttonLabel'] as String
            : hasFinalizedAttendance
            ? 'Attendance Recorded'
            : hasActiveAttendance
            ? 'Resume Event'
            : 'Join Event';
        final buttonColor = isActive && !hasFinalizedAttendance
            ? _primaryGreen
            : Colors.grey.shade400;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isActive ? _lightGreenBg : Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isActive ? Icons.sensors : Icons.schedule,
                      color: isActive ? _primaryGreen : Colors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActive ? 'Active Event' : 'Upcoming Event',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _darkText,
                        ),
                      ),
                      Text(
                        isActive ? 'You can check in now' : 'Available later',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _lightGreenBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['title'] ?? 'Untitled Event',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: _primaryGreen,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['venueName'] ?? 'Unknown',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _darkText,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                data['venueAddress'] ?? '',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 18, color: _primaryGreen),
                        const SizedBox(width: 8),
                        Text(
                          '${_formatTime(data['startTime'])} - ${_formatTime(data['endTime'])}',
                          style: TextStyle(color: _darkText, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: _primaryGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(data['startTime']),
                          style: TextStyle(color: _darkText, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: bannerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: bannerColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isActive
                                    ? Icons.timer_outlined
                                    : Icons.info_outline,
                                size: 16,
                                color: bannerColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                windowInfo['bannerText'] as String,
                                style: TextStyle(
                                  color: _darkText,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (windowInfo['bannerSubtext'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              windowInfo['bannerSubtext'] as String,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (attendanceRecord != null) ...[
                      const SizedBox(height: 12),
                      _buildAttendanceSummaryCard(
                        attendanceRecord,
                        summaryStatus ?? 'Recorded',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isActive && !hasFinalizedAttendance
                      ? () => _joinEventWithOSPermission(eventId, data)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: isActive && !hasFinalizedAttendance ? 2 : 0,
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttendanceSummaryCard(
    AttendanceSessionRecord record,
    String summaryStatus,
  ) {
    final style = _getAttendanceStatusStyle(summaryStatus);
    final displayStatus = _displayAttendanceStatus(summaryStatus);
    final displayedOutsideSeconds = record.displayOutsideSecondsAt(
      DateTime.now(),
    );
    final details = record.isFinalized
        ? 'You already finished this event with $displayStatus. Time away: ${_formatDuration(displayedOutsideSeconds)}.'
        : 'Your attendance is still active. Time away so far: ${_formatDuration(displayedOutsideSeconds)}.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style['bg'] as Color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (style['color'] as Color).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            style['icon'] as IconData,
            color: style['color'] as Color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.isFinalized
                      ? 'Attendance saved'
                      : 'Attendance in progress',
                  style: TextStyle(
                    color: style['color'] as Color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(details, style: TextStyle(color: _darkText, fontSize: 12)),
              ],
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
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _darkText,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history, color: Colors.purple),
            ),
            title: Text(
              'My Attendance',
              style: TextStyle(fontWeight: FontWeight.bold, color: _darkText),
            ),
            subtitle: const Text(
              'Review your past event check-ins',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => setState(() => _selectedIndex = 2),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primaryGreen),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: _darkText,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: _darkText, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _lightGreenBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _primaryGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _darkText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: _darkText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month_outlined),
          activeIcon: Icon(Icons.calendar_month),
          label: 'Calendar',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          label: 'Settings',
        ),
      ],
    );
  }
}

class _AttendanceDataSource extends DataTableSource {
  final List<QueryDocumentSnapshot> docs;

  _AttendanceDataSource(this.docs);

  @override
  DataRow? getRow(int index) {
    if (index >= docs.length) return null;
    
    final doc = docs[index];
    final data = doc.data() as Map<String, dynamic>;
    final eventName = data['eventName'] ?? data['eventTitle'] ?? 'Legacy Event';
    
    String eventTypeStr = 'Standard';
    final type = data['eventType'];
    if (type == 'type1_in_out') {
      eventTypeStr = 'Time In/Out';
    } else if (type == 'type2_continuous') {
      eventTypeStr = 'Continuous';
    }
    
    final timeIn = data['timeIn'] as Timestamp?;
    final dateStr = timeIn != null ? DateFormat('MMM d, yyyy - hh:mm a').format(timeIn.toDate()) : 'Unknown';
    
    final status = data['status']?.toString() ?? 'Absent';
    Color statusColor = Colors.red;
    if (status == 'Present') {
      statusColor = Colors.green;
    } else if (status == 'Late' || status == 'Partial') {
      statusColor = Colors.orange;
    }
    
    final pts = data['pointsAwarded'] ?? AttendancePolicy.getPointsForStatus(status);
    
    return DataRow(cells: [
      DataCell(Text(eventName)),
      DataCell(Text(eventTypeStr)),
      DataCell(Text(dateStr)),
      DataCell(Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold))),
      DataCell(Text('+$pts pts', style: const TextStyle(fontWeight: FontWeight.bold))),
    ]);
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => docs.length;

  @override
  int get selectedRowCount => 0;
}