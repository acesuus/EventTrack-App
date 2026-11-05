import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_policy.dart';
import 'geofencing_service.dart';
import 'joined_events_store.dart';
import 'widgets/student_ui.dart';

class EventTrackingScreen extends StatefulWidget {
  final String studentId;
  final String eventId;
  final Map<String, dynamic> eventData;

  const EventTrackingScreen({
    super.key,
    required this.studentId,
    required this.eventId,
    required this.eventData,
  });

  @override
  State<EventTrackingScreen> createState() => _EventTrackingScreenState();
}

class _EventTrackingScreenState extends State<EventTrackingScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Color _primaryGreen = StudentUi.green;
  final Color _darkText = StudentUi.ink;

  double get _eventRadius =>
      (widget.eventData['radius'] as num?)?.toDouble() ?? 50.0;

  List<LatLng> get _eventPolygon {
    final rawPoints = widget.eventData['polygonPoints'] as List<dynamic>?;
    if (rawPoints == null) return [];
    return rawPoints.map((point) {
      final p = Map<String, dynamic>.from(point as Map);
      return LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    }).toList();
  }

  bool _isInside = false;
  bool _isCheckingLocation = true;
  bool _hasShownSpoofingWarning = false;
  bool _attendanceFinalized = false;
  String? _attendanceStatus;
  Timestamp? _timeIn;
  Timestamp? _timeOut;
  Position? _currentPosition;
  double? _distanceToVenueMeters;
  String? _locationError;
  String _currentStatus = 'Loading...';

  @override
  void initState() {
    super.initState();
    unawaited(_rememberJoinedEvent());
    _checkAndLogLocation();
  }

  Future<void> _rememberJoinedEvent() async {
    try {
      await JoinedEventsStore.instance.join(widget.studentId, widget.eventId);
    } catch (error) {
      debugPrint('Could not save joined event: $error');
    }
  }

  Future<void> _backToDashboard() async {
    await _rememberJoinedEvent();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _attendanceRef => _firestore
      .collection('attendance')
      .doc('${widget.studentId}_${widget.eventId}');

  LatLng get _eventPoint => LatLng(
    (widget.eventData['lat'] as num).toDouble(),
    (widget.eventData['lng'] as num).toDouble(),
  );

  Timestamp get _eventStartTimestamp =>
      widget.eventData['startTime'] as Timestamp;

  Timestamp get _eventEndTimestamp => widget.eventData['endTime'] as Timestamp;

  String get _eventTitle => widget.eventData['title']?.toString() ?? 'Event';

  String get _eventType =>
      widget.eventData['eventType']?.toString() ??
      AttendancePolicy.eventTypeContinuous;

  LatLng? get _studentPoint => _currentPosition == null
      ? null
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  LocationSettings _buildLocationSettings() {
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  Future<void> _checkAndLogLocation({bool checkOutRequested = false}) async {
    if (!mounted) return;
    setState(() {
      _isCheckingLocation = true;
      _locationError = null;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _locationError = 'Turn on location services';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _locationError = 'Location permission required';
      });
      return;
    }

    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (!mounted) return;
        setState(() {
          _isCheckingLocation = false;
          _locationError =
              'Weak GPS signal. Please step near a window or go outside.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Weak GPS signal. Please step near a window or go outside.',
            ),
          ),
        );
        return;
      }

      final distanceInMeters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _eventPoint.latitude,
        _eventPoint.longitude,
      );
      final currentlyInside = await GeofencingService.isStudentInsideEvent(
        pos,
        widget.eventData,
        useMock: false,
      );
      if (!mounted) return;

      if (pos.isMocked) {
        if (!mounted) return;
        setState(() {
          _isInside = false;
          _isCheckingLocation = false;
          _currentPosition = pos;
          _distanceToVenueMeters = distanceInMeters;
          _currentStatus = 'Spoofing Detected';
        });

        if (!_hasShownSpoofingWarning) {
          _hasShownSpoofingWarning = true;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Invalid Location', style: TextStyle(color: Colors.red)),
                ],
              ),
              content: const Text(
                'We detected the use of a mock location app or GPS spoofer. You cannot check into this event using fake coordinates.\n\nPlease disable the spoofer and rejoin the event.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  child: const Text('Exit Event'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final isOffline = prefs.containsKey('cached_today_events');

      if (isOffline) {
        if (!currentlyInside) {
          setState(() {
            _currentPosition = pos;
            _distanceToVenueMeters = distanceInMeters;
            _isInside = false;
            _isCheckingLocation = false;
            _locationError = null;
            _currentStatus = 'Outside Event Area';
          });
          return;
        } else {
          final queueStr = prefs.getString('offline_attendance_queue');
          List<dynamic> queue = queueStr != null ? jsonDecode(queueStr) : [];

          bool isDuplicate = queue.any(
            (item) => item['eventId'] == widget.eventId,
          );
          if (isDuplicate) {
            setState(() {
              _currentPosition = pos;
              _distanceToVenueMeters = distanceInMeters;
              _isInside = true;
              _isCheckingLocation = false;
              _locationError = null;
              _currentStatus = 'Inside Event Area';
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Attendance already recorded locally. Sync required.',
                  ),
                ),
              );
            }
            return;
          }

          final int basePoints =
              int.tryParse(widget.eventData['basePoints']?.toString() ?? '') ??
              10;

          final newRecord = {
            'eventId': widget.eventId,
            'eventName': widget.eventData['title'] ?? 'Unknown Event',
            'status': 'Present',
            'pointsAwarded': basePoints,
            'timestamp': DateTime.now().toIso8601String(),
          };

          queue.add(newRecord);
          await prefs.setString('offline_attendance_queue', jsonEncode(queue));
          if (!mounted) return;

          setState(() {
            _currentPosition = pos;
            _distanceToVenueMeters = distanceInMeters;
            _isInside = true;
            _isCheckingLocation = false;
            _locationError = null;
            _currentStatus = 'Inside Event Area';
            _attendanceStatus = 'Present';
            _timeIn = Timestamp.now();
            _attendanceFinalized = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Attendance recorded locally. Sync required.'),
              ),
            );
          }
          return;
        }
      }

      final now = Timestamp.now();
      await _processAttendanceLogic(
        currentlyInside,
        now,
        checkOutRequested: checkOutRequested,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _distanceToVenueMeters = distanceInMeters;
        _isInside = currentlyInside;
        _isCheckingLocation = false;
        _locationError = null;
      });
    } catch (e) {
      debugPrint('Error in location tracking: $e');
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _locationError = 'Unable to read current location';
      });
    }
  }

  Future<void> _processAttendanceLogic(
    bool currentlyInside,
    Timestamp now, {
    bool checkOutRequested = false,
  }) async {
    final docSnap = await _attendanceRef.get();
    Map<String, dynamic> data = docSnap.exists ? docSnap.data()! : {};

    String currentStatus = data['status'] as String? ?? 'Pending';
    Timestamp? timeIn = data['timeIn'] as Timestamp?;
    Timestamp? timeOut = data['timeOut'] as Timestamp?;
    Timestamp? lastVerified = data['lastVerified'] as Timestamp?;

    if (timeOut != null) {
      // Already finalized
      _applyLocalState(data, currentlyInside);
      return;
    }

    bool updated = false;

    if (_eventType == AttendancePolicy.eventTypeInOut) {
      data = AttendancePolicy.verifyInOutAttendance(
        existing: data,
        verifiedAt: now,
        eventStart: _eventStartTimestamp.toDate(),
        isInside: currentlyInside,
        checkOutRequested: checkOutRequested,
        lateCutoffMinutes: widget.eventData['lateCutoffMinutes'] ?? 15,
      );
      updated = data['timeIn'] != timeIn || data['timeOut'] != timeOut;
      if (checkOutRequested && timeIn != null && !currentlyInside && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return to the venue to check out.')),
        );
      }
    } else {
      // Type 2: Continuous Stay
      if (timeIn == null) {
        if (currentlyInside) {
          timeIn = now;
          currentStatus = AttendancePolicy.determineInitialStatus(
            checkInTime: now.toDate(),
            eventStart: _eventStartTimestamp.toDate(),
            lateCutoffMinutes: widget.eventData['lateCutoffMinutes'] ?? 15,
          );
          data['timeIn'] = timeIn;
          data['status'] = currentStatus;
          data['initialStatus'] = currentStatus;
          data['lastVerified'] = now;
          updated = true;
        }
      } else {
        if (currentlyInside) {
          data['lastVerified'] = now;
          updated = true;
        } else {
          // Student is outside. Check grace period.
          if (lastVerified != null) {
            final minsGone = now
                .toDate()
                .difference(lastVerified.toDate())
                .inMinutes;
            if (minsGone > 20) {
              currentStatus = 'Partial';
              data['status'] = currentStatus;
              updated = true;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'You have been outside for over 20 mins. Status changed to Partial.',
                    ),
                    backgroundColor: StudentUi.muted,
                  ),
                );
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Warning: You are outside the venue. Return within ${20 - minsGone} mins to avoid penalty.',
                    ),
                  ),
                );
              }
            }
          }
        }
      }
    }

    if (updated) {
      final int basePoints =
          int.tryParse(widget.eventData['basePoints']?.toString() ?? '') ?? 10;
      String finalStatus = data['status'] as String? ?? 'Present';
      int pointsAwarded = 0;
      if (finalStatus == 'Present') {
        pointsAwarded = basePoints;
      } else if (finalStatus == 'Late' || finalStatus == 'Partial') {
        pointsAwarded = (basePoints / 2).round();
      } else {
        pointsAwarded = 0;
      }

      data['studentId'] = widget.studentId;
      data['eventId'] = widget.eventId;
      data['eventTitle'] = _eventTitle;
      data['eventType'] = _eventType;
      data['eventName'] = widget.eventData['title'] ?? 'Unknown Event';
      data['pointsAwarded'] = pointsAwarded;
      await _attendanceRef.set(data, SetOptions(merge: true));
      if (checkOutRequested && data['timeOut'] != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checked out. Your attendance has been saved.'),
          ),
        );
      }
    }

    _applyLocalState(data, currentlyInside);
  }

  void _applyLocalState(Map<String, dynamic> data, bool currentlyInside) {
    _attendanceStatus = data['status'] as String?;
    _timeIn = data['timeIn'] as Timestamp?;
    _timeOut = data['timeOut'] as Timestamp?;
    _attendanceFinalized = _timeOut != null;

    if (_attendanceStatus == null) {
      _currentStatus = 'Outside Event Area';
    } else {
      _currentStatus = currentlyInside
          ? 'Inside Event Area'
          : 'Outside Event Area';
    }
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '--:--';
    return DateFormat('hh:mm a').format(timestamp.toDate());
  }

  String _formatDistance(double? distanceInMeters) {
    if (distanceInMeters == null) return '--';
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} m';
    }
    return '${(distanceInMeters / 1000).toStringAsFixed(2)} km';
  }

  String _formatAccuracy(Position? position) {
    if (position == null) return '--';
    final accuracy = position.accuracy;
    final label = accuracy <= 10
        ? 'High'
        : accuracy <= 25
        ? 'Medium'
        : 'Low';
    return '$label (${accuracy.toStringAsFixed(0)} m)';
  }

  String _displayAttendanceStatus(String status) {
    switch (status) {
      case 'Present':
        return 'On Time';
      case 'Late':
        return 'Late Check-In';
      case 'Partial':
        return 'Partial Attendance';
      default:
        return status;
    }
  }

  String get _statusTitle {
    if (_locationError != null) return _locationError!;
    if (_currentStatus == 'Spoofing Detected') return 'Spoofing Detected';
    if (_isCheckingLocation) return 'Checking your location';
    if (_attendanceStatus != null) {
      return _displayAttendanceStatus(_attendanceStatus!);
    }
    return _isInside ? 'Inside Event Area' : 'Outside Event Area';
  }

  String get _statusSubtitle {
    if (_isCheckingLocation) {
      return 'Please wait while we verify your position at the venue.';
    }
    if (_attendanceFinalized) {
      return 'Attendance saved as ${_attendanceStatus != null ? _displayAttendanceStatus(_attendanceStatus!) : 'Recorded'}.';
    }
    if (_locationError != null) {
      return 'Location is needed to validate attendance';
    }
    if (_attendanceStatus == null) {
      return 'Go to the event venue, then verify your location to check in.';
    }

    if (_eventType == AttendancePolicy.eventTypeInOut) {
      return 'You are checked in. Check out at the venue when you are ready to leave.';
    } else {
      if (!_isInside) {
        return 'You are outside the event area. Return within the grace period to avoid Partial status.';
      }
      return 'Your attendance is active. Verify your location regularly while at the venue.';
    }
  }

  Color _attendanceColor(String status) {
    switch (status) {
      case 'Late':
        return StudentUi.muted;
      case 'Partial':
        return StudentUi.muted;
      case 'Present':
      default:
        return _primaryGreen;
    }
  }

  IconData get _statusIcon {
    if (_currentStatus == 'Spoofing Detected' || _locationError != null) {
      return Icons.warning_amber_rounded;
    }
    if (_attendanceStatus == 'Late') return Icons.timer_outlined;
    if (_attendanceStatus == 'Partial') return Icons.error_outline;
    if (_attendanceStatus != null) return Icons.check_circle;
    return Icons.location_searching;
  }

  Color get _statusColor {
    if (_currentStatus == 'Spoofing Detected' || _locationError != null) {
      return Colors.red;
    }
    if (_isCheckingLocation) return StudentUi.muted;
    if (_attendanceStatus != null) {
      return _attendanceColor(_attendanceStatus!);
    }
    return _isInside ? _primaryGreen : StudentUi.muted;
  }

  LatLng get _mapCenter => _eventPoint;

  double get _mapZoom {
    final radius = _eventRadius;
    if (radius <= 100) return 18.0;
    if (radius <= 300) return 17.0;
    if (radius <= 1000) return 16.0;
    if (radius <= 3000) return 15.0;
    return 14.0;
  }

  Widget _buildLocationMap() {
    final studentPoint = _studentPoint;

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: StudentUi.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              key: ValueKey(
                '${_mapCenter.latitude.toStringAsFixed(5)}:${_mapCenter.longitude.toStringAsFixed(5)}:${_distanceToVenueMeters?.round() ?? 0}',
              ),
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _mapZoom,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.eventtrack.app',
                ),
                PolygonLayer(
                  polygons: [
                    if (_eventPolygon.isNotEmpty)
                      Polygon(
                        points: _eventPolygon,
                        color: _primaryGreen.withValues(alpha: 0.18),
                        borderColor: _primaryGreen,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _eventPoint,
                      width: 44,
                      height: 56,
                      child: Column(
                        children: [
                          Icon(
                            Icons.location_pin,
                            color: _primaryGreen,
                            size: 38,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'Event',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (studentPoint != null)
                      Marker(
                        point: studentPoint,
                        width: 72,
                        height: 42,
                        child: Column(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            if (_isCheckingLocation && _currentPosition == null)
              Container(
                color: Colors.white.withValues(alpha: 0.7),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  String get _verificationLabel {
    if (_isCheckingLocation) return 'Checking location…';
    if (_attendanceFinalized) return 'Attendance saved';
    if (_eventType == AttendancePolicy.eventTypeInOut && _timeIn != null) {
      return 'Check out';
    }
    return _timeIn == null ? 'Verify location & check in' : 'Verify location';
  }

  Widget _headerDetail(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildEventHeader() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: StudentUi.green,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _eventType == AttendancePolicy.eventTypeInOut
              ? 'CHECK IN / CHECK OUT'
              : 'CONTINUOUS ATTENDANCE',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _eventTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        _headerDetail(
          Icons.location_on_outlined,
          widget.eventData['venueName']?.toString() ?? 'Event venue',
        ),
        if (widget.eventData['venueAddress']?.toString().trim().isNotEmpty ==
            true)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Text(
              widget.eventData['venueAddress'].toString(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        _headerDetail(
          Icons.calendar_today_outlined,
          DateFormat('EEEE, MMM d, yyyy').format(_eventStartTimestamp.toDate()),
        ),
        _headerDetail(
          Icons.schedule,
          '${_formatTime(_eventStartTimestamp)} – ${_formatTime(_eventEndTimestamp)}',
        ),
      ],
    ),
  );

  Widget _sectionHeading(IconData icon, String title) => Row(
    children: [
      Icon(icon, size: 21, color: StudentUi.green),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: StudentUi.ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) unawaited(_rememberJoinedEvent());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEAF9F1),
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to dashboard',
            onPressed: _backToDashboard,
            icon: const Icon(Icons.arrow_back),
          ),
          backgroundColor: StudentUi.green,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Event attendance',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: StudentUi.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _isCheckingLocation || _attendanceFinalized
                        ? null
                        : () => _checkAndLogLocation(
                            checkOutRequested:
                                _eventType == AttendancePolicy.eventTypeInOut &&
                                _timeIn != null,
                          ),
                    icon: Icon(
                      _attendanceFinalized ? Icons.check : Icons.my_location,
                      size: 20,
                    ),
                    label: Text(
                      _verificationLabel,
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: StudentUi.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFEDF0EE),
                      disabledForegroundColor: StudentUi.muted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _backToDashboard,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back to dashboard'),
                    style: TextButton.styleFrom(
                      foregroundColor: StudentUi.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEventHeader(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: StudentTrackingStatus(
                  title: _statusTitle,
                  description: _statusSubtitle,
                  icon: _statusIcon,
                  color: _statusColor,
                  checking: _isCheckingLocation,
                ),
              ),
              const SizedBox(height: 24),
              _sectionHeading(Icons.map_outlined, 'Venue & location'),
              const SizedBox(height: 12),
              _buildLocationMap(),
              const SizedBox(height: 12),
              StudentSurface(
                child: Column(
                  children: [
                    _buildDataRow(
                      'Venue boundary',
                      _isCheckingLocation
                          ? 'Checking…'
                          : _locationError != null || _currentPosition == null
                          ? 'Unavailable'
                          : _isInside
                          ? 'Inside'
                          : 'Outside',
                      _isInside ? _primaryGreen : _darkText,
                    ),
                    const Divider(height: 20, color: StudentUi.line),
                    _buildDataRow(
                      'GPS accuracy',
                      _formatAccuracy(_currentPosition),
                      _darkText,
                    ),
                    const Divider(height: 20, color: StudentUi.line),
                    _buildDataRow(
                      'Distance to venue',
                      _formatDistance(_distanceToVenueMeters),
                      _darkText,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionHeading(Icons.fact_check_outlined, 'Attendance record'),
              const SizedBox(height: 12),
              StudentSurface(
                child: Column(
                  children: [
                    _buildDataRow(
                      'Checked in',
                      _timeIn != null
                          ? _formatTime(_timeIn)
                          : 'Not yet checked in',
                      _darkText,
                    ),
                    const Divider(height: 20, color: StudentUi.line),
                    _buildDataRow(
                      'Checked out',
                      _timeOut != null
                          ? _formatTime(_timeOut)
                          : 'Not yet checked out',
                      _darkText,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: StudentUi.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
