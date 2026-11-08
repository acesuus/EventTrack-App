import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'attendance_policy.dart';
import 'device_binding.dart';
import 'event_tracking_screen.dart';
import 'joined_events_store.dart';
import 'student_photo.dart';
import 'widgets/student_avatar.dart';
import 'widgets/eventtrack_brand.dart';
import 'student_consent_screen.dart';
import 'student_login_screen.dart';
import 'widgets/student_ui.dart';
import 'widgets/student_settings.dart';
import 'widgets/student_profile_edit_dialog.dart';

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

  final Color _primaryGreen = const Color(0xFF1E7F5A);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  String? _profileName;
  String? _profilePhoto;
  bool _photoBusy = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;
  String get _displayName => _profileName ?? widget.studentName;

  int _selectedIndex = 0;
  Timer? _clockRefreshTimer;
  bool _isSyncingAttendance = false;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _profileSubscription = _firestore
        .collection('users')
        .doc(widget.studentId)
        .snapshots()
        .listen(
          (snapshot) {
            final photo = snapshot.data()?['photoBase64']?.toString();
            if (mounted && photo != _profilePhoto) {
              setState(() => _profilePhoto = photo);
            }
            final name = snapshot.data()?['name']?.toString().trim();
            if (name != null && name.isNotEmpty) {
              unawaited(_applyProfileName(name));
            }
          },
          onError: (Object error) =>
              debugPrint('Profile name sync is temporarily unavailable.'),
        );
    JoinedEventsStore.instance.load(widget.studentId);
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
    _profileSubscription?.cancel();
    _clockRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    // Attendance saved offline is queued by Firestore under this login, so it
    // must reach the server before signing out or it would be rejected.
    final synced = await _firestore
        .waitForPendingWrites()
        .then((_) => true)
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          synced
              ? 'You will need to log in again to track attendance.'
              : 'Some attendance has not synced yet. Connect to the internet and wait a moment before logging out, or it will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(synced ? 'Log out' : 'Log out anyway'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (!DeviceBinding.keysToKeepOnLogout.contains(key)) {
        await prefs.remove(key);
      }
    }
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
        if (eventId == null ||
            eventId.isEmpty ||
            attendanceData['timeOut'] != null) {
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

  /// Closes this student's record once its event has ended.
  Future<bool> _normalizeAttendanceRecord({
    required DocumentReference<Map<String, dynamic>> attendanceRef,
    required Map<String, dynamic> attendanceData,
    required Map<String, dynamic> eventData,
    required DateTime now,
  }) async {
    final done = AttendancePolicy.finalizeIfEnded(
      attendanceData,
      eventData,
      now,
    );
    if (done == null) return false;
    // Not awaited: offline, Firestore queues the write.
    attendanceRef.set(done, SetOptions(merge: true)).catchError((Object e) {
      debugPrint('Could not finalize attendance: $e');
    });
    return true;
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
      existingAttendance = await attendanceRef.get();
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
      final refreshedAttendance = await attendanceRef.get();
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
      await DeviceBinding.bind(widget.studentId);
      // Fetch current position to ensure the GPS sensor is active
      await Geolocator.getCurrentPosition();
    } catch (e) {
      if (!mounted) return;

      final displayMessage = e is DeviceBindingException
          ? e.message
          : 'Failed to verify location. Please ensure GPS is enabled.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(displayMessage)));
      return;
    }

    if (!mounted) return;
    try {
      await JoinedEventsStore.instance.join(widget.studentId, eventId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this event. Please try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(
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
            stream: _firestore
                .collection('events')
                .orderBy('startTime')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return _buildLoadErrorState();
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
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
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
                          DateTime eventDate = (data['startTime'] as Timestamp)
                              .toDate();
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
                              style: TextStyle(color: Color(0xFF616161)),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filteredEvents.length,
                            itemBuilder: (context, index) {
                              final doc = filteredEvents[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final windowInfo = _getEventWindowInfo(
                                data,
                                DateTime.now(),
                              );
                              return _buildEventCard(doc.id, data, windowInfo);
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
            final pts =
                data['pointsAwarded'] ??
                AttendancePolicy.getPointsForStatus(status);
            totalPoints += (pts as num).toInt();
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => setState(() {
                _selectedIndex = 2;
              }),
              borderRadius: BorderRadius.circular(24),
              child: Ink(
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
                      child: const Icon(
                        Icons.stars,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CS Association Points',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            snapshot.hasData ? '$totalPoints pts' : '— pts',
                            semanticsLabel: snapshot.hasData
                                ? '$totalPoints points'
                                : 'Loading points',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              Text(
                                'View breakdown',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
              if (snapshot.hasError) return _buildLoadErrorState();
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
                final aTime =
                    (aData['timeIn'] as Timestamp?)?.millisecondsSinceEpoch ??
                    0;
                final bTime =
                    (bData['timeIn'] as Timestamp?)?.millisecondsSinceEpoch ??
                    0;
                return bTime.compareTo(aTime);
              });

              int totalPoints = 0;
              for (var doc in records) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status']?.toString() ?? 'Absent';
                final pts =
                    data['pointsAwarded'] ??
                    AttendancePolicy.getPointsForStatus(status);
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
                          style: TextStyle(
                            color: Color(0xFF616161),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
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
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _AttendanceRecordTile(
                        data: records[index].data() as Map<String, dynamic>,
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

  Future<void> _applyProfileName(String name) async {
    if (!mounted) return;
    if (name != _displayName) setState(() => _profileName = name);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || name != _displayName) return;
      if (prefs.getString('studentId') == widget.studentId &&
          prefs.getString('studentName') != name) {
        await prefs.setString('studentName', name);
      }
    } catch (_) {
      debugPrint(
        'Profile is saved; the local name cache could not be refreshed.',
      );
    }
  }

  Future<void> _showEditProfileDialog(
    String currentName,
    String currentEmail,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudentProfileEditDialog(
        name: currentName,
        email: currentEmail == 'No email saved' ? '' : currentEmail,
        studentId: widget.studentId,
        onSave: (name) async {
          // Update the personal profile; the official roster remains admin-managed.
          await _firestore.collection('users').doc(widget.studentId).update({
            'name': name,
            'email': currentEmail,
          });
          await _applyProfileName(name);
        },
      ),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
  }

  Future<void> _updateProfilePhoto({bool remove = false}) async {
    if (_photoBusy) return;
    setState(() => _photoBusy = true);
    try {
      String? photo;
      if (!remove) {
        final selection = await fp.FilePicker.platform.pickFiles(
          type: fp.FileType.image,
          allowMultiple: false,
          withData: true,
        );
        if (selection == null) return;
        final file = selection.files.single;
        if (file.size > StudentPhoto.maxSourceBytes) {
          throw const FormatException('Choose an image smaller than 12 MB.');
        }
        final bytes =
            file.bytes ??
            (file.path == null ? null : await File(file.path!).readAsBytes());
        if (bytes == null) {
          throw const FormatException(
            'Could not open this image. Choose another photo.',
          );
        }
        photo = await StudentPhoto.prepare(bytes);
      }
      await _firestore.collection('users').doc(widget.studentId).update({
        'photoBase64': remove ? FieldValue.delete() : photo,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _profilePhoto = photo);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remove ? 'Profile photo removed.' : 'Profile photo updated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException
                ? error.message
                : 'Could not update your photo. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
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
              // The school email is the one they log in with.
              final rawEmail =
                  FirebaseAuth.instance.currentUser?.email ??
                  userData['email']?.toString().trim() ??
                  '';
              final email = rawEmail.contains('@')
                  ? rawEmail
                  : 'No email saved';
              final name = userData['name']?.toString() ?? _displayName;
              final deviceProtected =
                  deviceId.isNotEmpty && deviceId != 'Not registered';

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: _primaryGreen),
                );
              }
              if (snapshot.hasError && !snapshot.hasData) {
                return _buildEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load your details',
                  subtitle: 'Check your connection and open Settings again.',
                );
              }
              return StudentSettingsContent(
                name: name,
                studentId: widget.studentId,
                email: email,
                program: userData['program']?.toString() ?? '',
                yearBlock: userData['yearBlock']?.toString() ?? '',
                hasConsented: hasConsented,
                deviceProtected: deviceProtected,
                photoBase64: userData['photoBase64']?.toString(),
                photoBusy: _photoBusy,
                onPhotoChange: () => _updateProfilePhoto(),
                onPhotoRemove: () => _updateProfilePhoto(remove: true),
                onEdit: () => _showEditProfileDialog(name, email),
                onPrivacy: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentConsentScreen(
                        studentId: widget.studentId,
                        studentName: name,
                      ),
                    ),
                  );
                },
                onLocation: () => Geolocator.openLocationSettings(),
                onPermissions: () => Geolocator.openAppSettings(),
                onLogout: _handleLogout,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EventTrackBrand(color: Colors.white, size: 24),
                const SizedBox(height: 14),
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StudentAvatar(
                      name: _displayName,
                      photoBase64: _profilePhoto,
                      size: 38,
                      background: Colors.white,
                      foreground: StudentUi.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'ID: ${widget.studentId}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: _handleLogout,
                tooltip: 'Log out',
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
          const EventTrackBrand(color: Colors.white, size: 22),
          const SizedBox(height: 14),
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
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('events').orderBy('startTime').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildLoadErrorState();
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
                style: TextStyle(color: Color(0xFF616161)),
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
                style: TextStyle(color: Color(0xFF616161)),
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
    if (!isActive) return _buildScheduledEventCard(eventId, data, windowInfo);

    return ListenableBuilder(
      listenable: JoinedEventsStore.instance,
      builder: (context, _) =>
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
              final hasFinalizedAttendance =
                  attendanceRecord?.isFinalized == true;
              final hasJoinedEvent =
                  hasActiveAttendance ||
                  JoinedEventsStore.instance.contains(
                    widget.studentId,
                    eventId,
                  );
              final summaryStatus = attendanceRecord?.currentSummaryStatus;
              final buttonLabel = !isActive
                  ? windowInfo['buttonLabel'] as String
                  : hasFinalizedAttendance
                  ? 'Attendance Recorded'
                  : hasJoinedEvent
                  ? 'Resume Event'
                  : 'Join Event';
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: StudentEventCard(
                  details: StudentEventDetails(
                    title: data['title']?.toString() ?? 'Untitled event',
                    venue:
                        data['venueName']?.toString() ??
                        'Venue to be announced',
                    address: data['venueAddress']?.toString() ?? '',
                    time:
                        '${_formatTime(data['startTime'])} – ${_formatTime(data['endTime'])}',
                    date: _formatDate(data['startTime']),
                  ),
                  status: hasFinalizedAttendance
                      ? 'Attendance saved'
                      : hasActiveAttendance
                      ? 'Attendance in progress'
                      : hasJoinedEvent
                      ? 'Event joined'
                      : windowInfo['bannerText'] as String,
                  statusDetail: hasJoinedEvent && attendanceRecord == null
                      ? 'Check in at the venue'
                      : windowInfo['bannerSubtext'] as String?,
                  isActive: isActive,
                  buttonLabel: buttonLabel,
                  onJoin: isActive && !hasFinalizedAttendance
                      ? () => _joinEventWithOSPermission(eventId, data)
                      : null,
                  attendance: attendanceRecord == null
                      ? null
                      : _buildActiveAttendanceSummaryCard(
                          attendanceRecord,
                          summaryStatus ?? 'Recorded',
                        ),
                ),
              );
            },
          ),
    );
  }

  Widget _buildScheduledEventCard(
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
                          color: Color(0xFF616161),
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
                                  color: Color(0xFF616161),
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
                                color: Color(0xFF616161),
                                fontSize: 12,
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

  Widget _buildActiveAttendanceSummaryCard(
    AttendanceSessionRecord record,
    String summaryStatus,
  ) {
    final style = {
      ..._getAttendanceStatusStyle(summaryStatus),
      'color': summaryStatus.toLowerCase() == 'present'
          ? _primaryGreen
          : StudentUi.muted,
    };
    final displayStatus = _displayAttendanceStatus(summaryStatus);
    final displayedOutsideSeconds = record.displayOutsideSecondsAt(
      DateTime.now(),
    );
    final details = record.isFinalized
        ? 'You already finished this event with $displayStatus. Time away: ${_formatDuration(displayedOutsideSeconds)}.'
        : 'Your attendance is still active. Time away so far: ${_formatDuration(displayedOutsideSeconds)}.';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
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
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF616161)),
            onTap: () => setState(() => _selectedIndex = 2),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadErrorState() => _buildEmptyState(
    icon: Icons.cloud_off,
    title: "Couldn't load data",
    subtitle:
        'Check your internet connection. This will update automatically when you are back online.',
  );

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
            Icon(icon, size: 60, color: Colors.grey.shade600),
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
              style: const TextStyle(color: Color(0xFF616161)),
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
      unselectedItemColor: Color(0xFF616161),
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

class _AttendanceRecordTile extends StatelessWidget {
  const _AttendanceRecordTile({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final eventName =
        (data['eventName'] ?? data['eventTitle'] ?? 'Legacy Event').toString();
    final type = data['eventType'];
    final eventType = type == 'type1_in_out'
        ? 'Time In/Out'
        : (type == 'type2_continuous' ? 'Continuous' : 'Standard');
    final timeIn = data['timeIn'] as Timestamp?;
    final date = timeIn != null
        ? DateFormat('MMM d, yyyy · hh:mm a').format(timeIn.toDate())
        : 'Unknown date';
    final status = data['status']?.toString() ?? 'Absent';
    final statusColor = status == 'Present'
        ? Colors.green.shade800
        : (status == 'Late' || status == 'Partial')
        ? Colors.orange.shade900
        : Colors.red.shade700;
    final pts =
        data['pointsAwarded'] ?? AttendancePolicy.getPointsForStatus(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C2D48),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$eventType · $date',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF616161),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '+$pts pts',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
