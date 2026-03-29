import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'attendance_policy.dart';

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
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _darkText = const Color(0xFF0C2D48);

  StreamSubscription<Position>? _positionStream;
  bool _isInside = false;
  bool _isCheckingLocation = true;
  bool _hasShownSpoofingWarning = false;
  bool _isFinishing = false;
  bool _attendanceFinalized = false;
  String? _attendanceStatus;
  Timestamp? _timeIn;
  Timestamp? _timeOut;
  int _totalOutsideSeconds = 0;
  int _sessionCount = 0;
  Position? _currentPosition;
  double? _distanceToVenueMeters;
  String? _locationError;
  String _currentStatus = 'Loading...';

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _attendanceRef => _firestore
      .collection('attendance')
      .doc('${widget.studentId}_${widget.eventId}');

  LatLng get _eventPoint => LatLng(
    (widget.eventData['lat'] as num).toDouble(),
    (widget.eventData['lng'] as num).toDouble(),
  );

  double get _eventRadius => (widget.eventData['radius'] as num).toDouble();

  Timestamp get _eventStartTimestamp =>
      widget.eventData['startTime'] as Timestamp;

  Timestamp get _eventEndTimestamp => widget.eventData['endTime'] as Timestamp;

  String get _eventTitle => widget.eventData['title']?.toString() ?? 'Event';

  LatLng? get _studentPoint => _currentPosition == null
      ? null
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  LocationSettings _buildLocationSettings() {
    return AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 2),
      forceLocationManager: true,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'EventTrack location active',
        notificationText: 'Checking attendance location',
        enableWakeLock: true,
      ),
    );
  }

  Future<void> _startLocationTracking() async {
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
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: _buildLocationSettings(),
      );
      await _checkAndLogLocation(initialPosition);
    } catch (e) {
      debugPrint('Error fetching initial location: $e');
    }

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: _buildLocationSettings(),
        ).listen(
          (position) async => _checkAndLogLocation(position),
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _isCheckingLocation = false;
              _locationError = 'Unable to update location';
            });
          },
        );
  }

  Future<void> _checkAndLogLocation([Position? latestPosition]) async {
    try {
      final pos =
          latestPosition ??
          await Geolocator.getCurrentPosition(
            locationSettings: _buildLocationSettings(),
          );

      final distanceInMeters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _eventPoint.latitude,
        _eventPoint.longitude,
      );
      final currentlyInside = distanceInMeters <= _eventRadius;

      if (pos.isMocked) {
        if (!mounted) return;
        setState(() {
          _isInside = false;
          _isCheckingLocation = false;
          _currentPosition = pos;
          _distanceToVenueMeters = distanceInMeters;
          _currentStatus = 'Spoofing Detected';
        });

        _positionStream?.cancel();

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

      final now = Timestamp.now();
      final record = await _resolveAttendanceRecord(
        currentlyInside: currentlyInside,
        now: now,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _distanceToVenueMeters = distanceInMeters;
        _isInside = currentlyInside;
        _isCheckingLocation = false;
        _locationError = null;
        _applyRecordToLocalState(record);
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

  Future<AttendanceSessionRecord?> _resolveAttendanceRecord({
    required bool currentlyInside,
    required Timestamp now,
  }) async {
    final docSnap = await _attendanceRef.get();
    AttendanceSessionRecord? record = docSnap.exists
        ? AttendanceSessionRecord.fromFirestore(docSnap.data())
        : null;

    if (record != null && record.needsLegacyBootstrap) {
      record = record.bootstrapLegacyIfNeeded(fallbackStart: now);
      await _persistRecord(record);
    }

    if (record != null &&
        AttendancePolicy.shouldAutoFinalize(
          timeOut: record.timeOut,
          eventEnd: _eventEndTimestamp.toDate(),
          now: now.toDate(),
        )) {
      record = record.finalize(_eventEndTimestamp);
      await _persistRecord(record);
      return record;
    }

    if (record == null) {
      if (!currentlyInside) {
        return null;
      }

      final initialStatus = AttendancePolicy.determineInitialStatus(
        checkInTime: now.toDate(),
        eventStart: _eventStartTimestamp.toDate(),
        lateCutoffMinutes: widget.eventData['lateCutoffMinutes'] ?? 15,
      );
      record = AttendanceSessionRecord.createInitial(
        initialStatus: initialStatus,
        startedAt: now,
      );
      await _persistRecord(record);
      return record;
    }

    if (record.isFinalized) {
      return record;
    }

    final transitioned = currentlyInside
        ? record.enterGeofence(now)
        : record.leaveGeofence(now);

    if (!identical(transitioned, record)) {
      record = transitioned;
      await _persistRecord(record);
    }

    return record;
  }

  Future<void> _persistRecord(AttendanceSessionRecord record) async {
    await _attendanceRef.set(
      record.toFirestoreFields(
        studentId: widget.studentId,
        eventId: widget.eventId,
        eventTitle: _eventTitle,
      ),
      SetOptions(merge: true),
    );
  }

  void _applyRecordToLocalState(AttendanceSessionRecord? record) {
    if (record == null) {
      _attendanceStatus = null;
      _timeIn = null;
      _timeOut = null;
      _attendanceFinalized = false;
      _totalOutsideSeconds = 0;
      _sessionCount = 0;
      _currentStatus = 'Outside Event Area';
      return;
    }

    _attendanceStatus = record.currentSummaryStatus;
    _timeIn = record.timeIn;
    _timeOut = record.timeOut;
    _attendanceFinalized = record.isFinalized;
    _totalOutsideSeconds = record.displayOutsideSecondsAt(DateTime.now());
    _sessionCount = record.sessions.length;
    _currentStatus = _isInside ? 'Inside Event Area' : 'Outside Event Area';
  }

  Future<void> _finishAttendance() async {
    if (_attendanceFinalized || _attendanceStatus == null) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Finish Attendance?'),
            content: const Text(
              'This will close your attendance for this event. Final status will be based on your first check-in and total time spent outside the geofence.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Finish',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    if (mounted) {
      setState(() {
        _isFinishing = true;
      });
    }

    _positionStream?.cancel();

    final attendanceSnap = await _attendanceRef.get();
    if (!attendanceSnap.exists) {
      if (!mounted) return;
      setState(() {
        _isFinishing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Exited event monitor. No attendance record was created because you never checked in.',
          ),
          backgroundColor: _darkText,
        ),
      );
      Navigator.pop(context);
      return;
    }

    var record = AttendanceSessionRecord.fromFirestore(attendanceSnap.data());
    if (record.needsLegacyBootstrap) {
      record = record.bootstrapLegacyIfNeeded(fallbackStart: Timestamp.now());
    }
    record = record.finalize(Timestamp.now());
    await _persistRecord(record);

    if (!mounted) return;
    setState(() {
      _applyRecordToLocalState(record);
      _isFinishing = false;
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Attendance Saved'),
        content: Text(
          'Your final result is ${_displayAttendanceStatus(record.status)}. You can review it later in My Attendance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pop(context);
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes == 0) {
      return '${remainingSeconds}s';
    }
    return '${minutes}m ${remainingSeconds}s';
  }

  int get _returnCount => _sessionCount <= 1 ? 0 : _sessionCount - 1;

  String _formatReturnCount() {
    if (_returnCount == 0) return '0';
    if (_returnCount == 1) return '1 return';
    return '$_returnCount returns';
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
    if (_isCheckingLocation) return 'Searching Location...';
    if (_attendanceStatus != null) {
      return _displayAttendanceStatus(_attendanceStatus!);
    }
    return _isInside ? 'Inside Event Area' : 'Outside Event Area';
  }

  String get _statusSubtitle {
    if (_attendanceFinalized) {
      return 'Attendance saved as ${_attendanceStatus != null ? _displayAttendanceStatus(_attendanceStatus!) : 'Recorded'}. You were away for ${_formatDuration(_totalOutsideSeconds)} and returned ${_formatReturnCount()}.';
    }
    if (_locationError != null) {
      return 'Location is needed to validate attendance';
    }
    if (_attendanceStatus == null) {
      return 'Move inside the event geofence to check in.';
    }
    if (!_isInside) {
      return 'You are outside the event area right now, but your attendance is still active. Return within 15 minutes total away time to keep ${_displayAttendanceStatus(_attendanceStatus!)}.';
    }
    return 'Your attendance is active. You may leave and come back while the event is still ongoing.';
  }

  Color _attendanceColor(String status) {
    switch (status) {
      case 'Late':
        return Colors.orange;
      case 'Partial':
        return Colors.amber.shade700;
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
    if (_isCheckingLocation) return Colors.orange;
    if (_attendanceStatus != null) {
      return _attendanceColor(_attendanceStatus!);
    }
    return _isInside ? _primaryGreen : Colors.orange;
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
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _eventPoint,
                      useRadiusInMeter: true,
                      radius: _eventRadius,
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
                              borderRadius: BorderRadius.circular(10),
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
                                borderRadius: BorderRadius.circular(10),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF9F1),
      appBar: AppBar(
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Event Tracking',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Live monitoring active',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Icon(_statusIcon, color: _statusColor, size: 60),
                  const SizedBox(height: 12),
                  Text(
                    _statusTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _darkText, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _darkText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: _primaryGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.eventData['venueName'] ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _darkText,
                              ),
                            ),
                            Text(
                              widget.eventData['venueAddress'] ?? '',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
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
                      Icon(Icons.access_time, color: _primaryGreen, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatTime(_eventStartTimestamp)} - ${_formatTime(_eventEndTimestamp)}',
                        style: TextStyle(color: _darkText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Location Status',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _darkText,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _isInside
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: _isInside
                                      ? _primaryGreen
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isInside ? 'Inside' : 'Outside',
                                  style: TextStyle(
                                    color: _isInside
                                        ? _primaryGreen
                                        : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh location',
                            onPressed: () => _checkAndLogLocation(),
                            icon: Icon(Icons.refresh, color: _primaryGreen),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildLocationMap(),
                  const SizedBox(height: 16),
                  _buildDataRow(
                    'Location Accuracy',
                    _formatAccuracy(_currentPosition),
                    _primaryGreen,
                  ),
                  const Divider(),
                  _buildDataRow(
                    'Distance from Event',
                    _formatDistance(_distanceToVenueMeters),
                    _darkText,
                  ),
                  const Divider(),
                  _buildDataRow(
                    'Allowed Area',
                    '${_eventRadius.toStringAsFixed(0)} m',
                    _darkText,
                  ),
                  const Divider(),
                  _buildDataRow(
                    'Time Away from Event',
                    _formatDuration(_totalOutsideSeconds),
                    _darkText,
                  ),
                  const Divider(),
                  _buildDataRow(
                    'Returns to Event',
                    _formatReturnCount(),
                    _darkText,
                  ),
                  const Divider(),
                  _buildDataRow(
                    'Checked In At',
                    _timeIn != null ? _formatTime(_timeIn) : '--:--',
                    _darkText,
                  ),
                  const Divider(),
                  _buildDataRow(
                    'Finished At',
                    _timeOut != null ? _formatTime(_timeOut) : '--:--',
                    _darkText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isFinishing ? null : _finishAttendance,
                icon: Icon(
                  _isFinishing
                      ? Icons.hourglass_top
                      : _attendanceFinalized || _attendanceStatus == null
                      ? Icons.arrow_back
                      : Icons.task_alt,
                  color: Colors.white,
                ),
                label: Text(
                  _isFinishing
                      ? 'Saving Attendance...'
                      : _attendanceFinalized || _attendanceStatus == null
                      ? 'Back to Dashboard'
                      : 'Finish Attendance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade500,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'The map shows the event area and your current location. Temporary exits are allowed while the event is active, but staying away for more than 15 minutes total will mark your attendance as Partial Attendance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
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
          Text(label, style: const TextStyle(color: Colors.grey)),
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
