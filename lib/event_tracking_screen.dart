import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'attendance_policy.dart';
import 'core/permission_service.dart';
import 'core/security_service.dart';
import 'geofencing_service.dart';
import 'joined_events_store.dart';
import 'utils/security_utils.dart';
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
      (_event['radius'] as num?)?.toDouble() ?? 50.0;

  List<LatLng> get _eventPolygon {
    final rawPoints = _event['polygonPoints'] as List<dynamic>?;
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

  /// The attendance record as last saved; kept in memory so tracking works offline.
  Map<String, dynamic> _record = {};
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _eventSubscription;
  bool _eventDeleted = false;

  /// Latest event details; the admin may edit or end the event while this screen is open.
  late Map<String, dynamic> _event = widget.eventData;
  Timer? _keepAliveTimer;
  Timer? _eventEndTimer;
  DateTime? _lastPositionAt;
  bool _isProcessing = false;

  /// Readings less precise than this are shown but never change attendance.
  static const double _maxAccuracyMeters = 50;

  @override
  void initState() {
    super.initState();
    // Close this screen if the admin deletes the event while it is open.
    _eventSubscription = _firestore
        .collection('events')
        .doc(widget.eventId)
        .snapshots()
        .listen((snap) {
          if (snap.exists) {
            unawaited(_rememberJoinedEvent());
            _onEventChanged(snap.data()!);
          } else if (!snap.metadata.isFromCache) {
            _onEventDeleted();
          }
        }, onError: (Object e) => debugPrint('Event watch failed: $e'));
    unawaited(_start());
  }

  void _onEventChanged(Map<String, dynamic> data) {
    final endChanged = data['endTime'] != _event['endTime'];
    if (!mounted) return;
    setState(() => _event = data);
    if (endChanged && _positionSubscription != null) {
      _scheduleEndTimer();
      unawaited(_finalizeIfEnded());
    }
  }

  void _scheduleEndTimer() {
    _eventEndTimer?.cancel();
    final untilEnd = _eventEndTimestamp.toDate().difference(DateTime.now());
    _eventEndTimer = Timer(untilEnd + const Duration(seconds: 5), () {
      unawaited(_finalizeIfEnded());
    });
  }

  void _onEventDeleted() {
    if (_eventDeleted || !mounted) return;
    _eventDeleted = true;
    _stopTracking();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('This event was deleted by the admin.')),
    );
  }

  Future<void> _rememberJoinedEvent() async {
    if (_eventDeleted) return;
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
    _eventSubscription?.cancel();
    _positionSubscription?.cancel();
    _keepAliveTimer?.cancel();
    _eventEndTimer?.cancel();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _attendanceRef => _firestore
      .collection('attendance')
      .doc('${widget.studentId}_${widget.eventId}');

  LatLng get _eventPoint => LatLng(
    (_event['lat'] as num).toDouble(),
    (_event['lng'] as num).toDouble(),
  );

  Timestamp get _eventStartTimestamp =>
      _event['startTime'] as Timestamp;

  Timestamp get _eventEndTimestamp => _event['endTime'] as Timestamp;

  String get _eventTitle => _event['title']?.toString() ?? 'Event';

  String get _eventType =>
      _event['eventType']?.toString() ??
      AttendancePolicy.eventTypeContinuous;

  bool get _isInOut => _eventType == AttendancePolicy.eventTypeInOut;

  List<AttendanceHalf> get _halves => AttendancePolicy.inOutHalves(_event);

  LatLng? get _studentPoint => _currentPosition == null
      ? null
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  /// Keeps location updates running while the phone is locked: a foreground
  /// service notification on Android, background location mode on iOS.
  LocationSettings _buildLocationSettings() {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'EventTrack is verifying your attendance',
          notificationText: 'Location is used only until this event ends.',
          enableWakeLock: true,
        ),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }

  Future<void> _start() async {
    try {
      final snap = await _attendanceRef.get();
      _record = snap.data() ?? {};
    } catch (e) {
      // Offline with nothing cached: start from an empty record.
      debugPrint('Attendance record unavailable offline: $e');
    }
    if (!mounted) return;
    setState(() => _applyLocalState(_isInside));
    if (await _finalizeIfEnded()) return;
    if (!await _ensureLocationAccess()) return;
    // Android 13+ hides the tracking notification without this; tracking works either way.
    await PermissionService.requestNotificationPermission();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(
      (pos) => unawaited(_handlePosition(pos)),
      onError: (Object e) {
        debugPrint('Location stream error: $e');
        if (mounted) setState(() => _locationError = 'Unable to read current location');
      },
    );

    // Stationary phones may stop reporting; ask for a fix so attendance keeps updating.
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final last = _lastPositionAt;
      if (last == null || DateTime.now().difference(last).inSeconds >= 60) {
        unawaited(_checkNow());
      }
    });

    _scheduleEndTimer();
  }

  Future<bool> _ensureLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      setState(() {
        _isCheckingLocation = false;
        _locationError = 'Turn on location services';
      });
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      setState(() {
        _isCheckingLocation = false;
        _locationError = 'Location permission required';
      });
      return false;
    }
    return true;
  }

  /// One-off reading, used by the button and when the stream goes quiet.
  Future<void> _checkNow({bool checkOutRequested = false}) async {
    if (_attendanceFinalized) return;
    if (!await _ensureLocationAccess()) return;
    if (mounted && checkOutRequested) setState(() => _isCheckingLocation = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await _handlePosition(pos, checkOutRequested: checkOutRequested);
    } catch (e) {
      debugPrint('Location check failed: $e');
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _locationError = 'Weak GPS signal. Please step near a window or go outside.';
      });
    }
  }

  Future<void> _handlePosition(
    Position pos, {
    bool checkOutRequested = false,
  }) async {
    _lastPositionAt = DateTime.now();
    if (_attendanceFinalized || _isProcessing) return;
    _isProcessing = true;
    try {
      await _processPosition(pos, checkOutRequested: checkOutRequested);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processPosition(
    Position pos, {
    required bool checkOutRequested,
  }) async {
    final distanceInMeters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      _eventPoint.latitude,
      _eventPoint.longitude,
    );

    try {
      await SecurityService.verifyDeviceSecurity(pos);
    } on SecurityException catch (e) {
      if (!mounted) return;
      setState(() {
        _isInside = false;
        _isCheckingLocation = false;
        _currentPosition = pos;
        _distanceToVenueMeters = distanceInMeters;
        _currentStatus = 'Spoofing Detected';
      });
      if (!_hasShownSpoofingWarning) {
        SecurityService.logViolation(
          widget.studentId,
          widget.eventId,
          e.message,
        );
      }
      _showSpoofingWarning(e.message);
      return;
    }

    bool currentlyInside;
    try {
      currentlyInside = await GeofencingService.isStudentInsideEvent(
        pos,
        _event,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _locationError = e.toString().replaceAll('Exception: ', '').replaceAll('SECURITY_VIOLATION: ', '');
      });
      return;
    }
    if (!mounted) return;

    setState(() {
      _currentPosition = pos;
      _distanceToVenueMeters = distanceInMeters;
      _isInside = currentlyInside;
      _isCheckingLocation = false;
      _locationError = null;
    });

    if (pos.accuracy > _maxAccuracyMeters) {
      if (checkOutRequested) {
        _showMessage('GPS is not precise enough yet. Step outside or near a window and try again.');
      }
      return;
    }

    final now = Timestamp.now();
    final Map<String, dynamic>? updated;
    if (_isInOut) {
      updated = AttendancePolicy.verifyInOutAttendance(
        existing: _record,
        verifiedAt: now,
        halves: _halves,
        isInside: currentlyInside,
        checkOutRequested: checkOutRequested,
        lateCutoffMinutes: AttendancePolicy.lateCutoffOf(_event),
        checkInOpenMinutes: AttendancePolicy.checkInOpenOf(_event),
      );
      if (updated == null && checkOutRequested) {
        _showMessage(_checkOutBlockedReason(currentlyInside, now.toDate()));
      }
    } else {
      final opens = _eventStartTimestamp.toDate().subtract(
        Duration(minutes: AttendancePolicy.checkInOpenOf(_event)),
      );
      final inWindow =
          !now.toDate().isBefore(opens) &&
          !now.toDate().isAfter(_eventEndTimestamp.toDate());
      updated = inWindow
          ? AttendancePolicy.verifyContinuousAttendance(
              existing: _record,
              verifiedAt: now,
              eventStart: _eventStartTimestamp.toDate(),
              isInside: currentlyInside,
              lateCutoffMinutes: AttendancePolicy.lateCutoffOf(_event),
              requirement: AttendancePolicy.requirementOf(
                _event,
                'continuousRequirement',
              ),
              eventEnd: _eventEndTimestamp.toDate(),
            )
          : null;
    }

    if (updated != null) _save(updated);
    if (!mounted) return;
    setState(() => _applyLocalState(currentlyInside));
  }

  String _checkOutBlockedReason(bool inside, DateTime now) {
    if (!inside) return 'Return to the venue to check out.';
    final index = AttendancePolicy.halfIndexAt(
      _halves,
      now,
      checkInOpenMinutes: AttendancePolicy.checkInOpenOf(_event),
    );
    if (index == null) return 'Check-out is not open right now.';
    final opens = AttendancePolicy.checkOutOpensAt(_halves[index]);
    return 'Check-out opens at ${DateFormat('h:mm a').format(opens)}.';
  }

  /// Saves without awaiting: offline, Firestore queues the write and syncs later.
  void _save(Map<String, dynamic> data) {
    if (_eventDeleted) return;
    final status = data['status']?.toString() ?? 'Present';
    _record = SecurityUtils.signed({
      ...data,
      'studentId': widget.studentId,
      'eventId': widget.eventId,
      'eventTitle': _eventTitle,
      'eventName': _eventTitle,
      'eventType': _eventType,
      'pointsAwarded': AttendancePolicy.pointsFor(
        status,
        AttendancePolicy.basePointsOf(_event),
      ),
    });
    final wasFinal = data['timeOut'] != null;
    _attendanceRef.set(_record, SetOptions(merge: true)).catchError((Object e) {
      debugPrint('Attendance save failed: $e');
      _showMessage("Couldn't save your attendance. Make sure you're logged in, then try again.");
    });
    if (wasFinal) {
      _stopTracking();
      _showMessage('Attendance saved as ${_displayAttendanceStatus(status)}.');
    }
  }

  Future<bool> _finalizeIfEnded() async {
    final done = AttendancePolicy.finalizeIfEnded(
      _record,
      _event,
      DateTime.now(),
    );
    if (done == null) {
      if (_record['timeOut'] != null) _stopTracking();
      return _record['timeOut'] != null;
    }
    if (_record['timeIn'] == null) {
      // Never checked in: nothing to save, the student is Absent.
      _stopTracking();
      if (mounted) setState(() => _locationError = 'This event has ended');
      return true;
    }
    _save(done);
    if (mounted) setState(() => _applyLocalState(_isInside));
    return true;
  }

  void _stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _keepAliveTimer?.cancel();
    _eventEndTimer?.cancel();
    if (mounted) setState(() => _isCheckingLocation = false);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSpoofingWarning(String reason) {
    if (_hasShownSpoofingWarning || !mounted) return;
    _hasShownSpoofingWarning = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Security check failed', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Text(
          '$reason Attendance can only be recorded on a real, unmodified phone with genuine GPS.\n\nFix this, then rejoin the event.',
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

  void _applyLocalState(bool currentlyInside) {
    _attendanceStatus = _record['status'] as String?;
    _timeIn = _record['timeIn'] as Timestamp?;
    _timeOut = _record['timeOut'] as Timestamp?;
    _attendanceFinalized = _timeOut != null;
    if (_attendanceFinalized) _isCheckingLocation = false;
    _currentStatus = currentlyInside ? 'Inside Event Area' : 'Outside Event Area';
  }

  /// The In/Out half the student can act on right now, or null between halves.
  int? get _currentHalfIndex => AttendancePolicy.halfIndexAt(
    _halves,
    DateTime.now(),
    checkInOpenMinutes: AttendancePolicy.checkInOpenOf(_event),
  );

  String _halfName(int index) =>
      _halves.length == 1 ? '' : (index == 0 ? ' (morning)' : ' (afternoon)');

  /// Seconds away from the venue so far (Continuous Stay only).
  int get _outsideSecondsNow =>
      AttendanceSessionRecord.fromFirestore(_record).displayOutsideSecondsAt(DateTime.now());

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
    if (_currentStatus == 'Spoofing Detected') return 'Security check failed';
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
    if (_isInOut) {
      final index = _currentHalfIndex;
      if (index == null) {
        final next = _halves.where((h) => h.start.isAfter(DateTime.now()));
        return next.isEmpty
            ? 'Check-in is closed for this event.'
            : 'Next check-in opens at ${DateFormat('h:mm a').format(next.first.start.subtract(Duration(minutes: AttendancePolicy.checkInOpenOf(_event))))}.';
      }
      final half = AttendancePolicy.halvesOf(_record, _halves.length)[index];
      final checkOutAt = DateFormat(
        'h:mm a',
      ).format(AttendancePolicy.checkOutOpensAt(_halves[index]));
      switch (_halves[index].requirement) {
        case AttendancePolicy.requireOut:
          return half['timeOut'] == null
              ? 'This session only needs a time out. Check out at the venue from $checkOutAt.'
              : 'Timed out${_halfName(index)}.';
        case AttendancePolicy.requireIn:
          return half['timeIn'] == null
              ? 'Go to the venue. You are checked in${_halfName(index)} automatically when your location is verified.'
              : 'Checked in${_halfName(index)}. This session doesn\'t need a time out.';
      }
      if (half['timeIn'] == null) {
        return 'Go to the venue. You are checked in${_halfName(index)} automatically when your location is verified.';
      }
      return 'Checked in${_halfName(index)}. Check out at the venue from $checkOutAt. Every session is needed to avoid Partial.';
    }
    final requirement = AttendancePolicy.requirementOf(
      _event,
      'continuousRequirement',
    );
    if (_attendanceStatus == null) {
      if (requirement == AttendancePolicy.requireOut) {
        final opens = _eventEndTimestamp.toDate().subtract(
          const Duration(
            minutes: AttendancePolicy.checkOutOpenMinutesBeforeEnd,
          ),
        );
        return 'Only your time out counts. Be at the venue from ${DateFormat('h:mm a').format(opens)} with this screen open.';
      }
      return 'Go to the venue. You are checked in automatically when your location is verified.';
    }
    if (requirement == AttendancePolicy.requireIn) {
      return 'You are checked in. This event only needs a time in, so leaving early won\'t change it.';
    }
    final awayMinutes = _outsideSecondsNow ~/ 60;
    final limit = AttendancePolicy.allowedOutsideSeconds ~/ 60;
    final away = awayMinutes > limit
        ? 'You have been away $awayMinutes min, more than the $limit min allowed, so this will be saved as Partial.'
        : 'Time away so far: $awayMinutes of $limit min allowed.';
    return 'Keep this screen open until the event ends. You can lock your phone. $away';
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
                                fontSize: 12,
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
                                  fontSize: 12,
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

  /// True when the button should check out of the current In/Out half.
  bool get _canRequestCheckOut {
    if (!_isInOut) return false;
    final index = _currentHalfIndex;
    if (index == null) return false;
    final half = AttendancePolicy.halvesOf(_record, _halves.length)[index];
    return switch (_halves[index].requirement) {
      AttendancePolicy.requireIn => false,
      AttendancePolicy.requireOut => half['timeOut'] == null,
      _ => half['timeIn'] != null && half['timeOut'] == null,
    };
  }

  String get _verificationLabel {
    if (_isCheckingLocation) return 'Checking location…';
    if (_attendanceFinalized) return 'Attendance saved';
    if (_canRequestCheckOut) return 'Check out${_halfName(_currentHalfIndex!)}';
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
            fontSize: 12,
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
          _event['venueName']?.toString() ?? 'Event venue',
        ),
        if (_event['venueAddress']?.toString().trim().isNotEmpty ==
            true)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Text(
              _event['venueAddress'].toString(),
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
                        : () => _checkNow(
                            checkOutRequested: _canRequestCheckOut,
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
                    if (_isInOut && _halves.length == 2)
                      for (final (i, half) in AttendancePolicy.halvesOf(_record, 2).indexed) ...[
                        _buildDataRow(
                          i == 0 ? 'Morning' : 'Afternoon',
                          '${_formatTime(half['timeIn'] as Timestamp?)} in · ${_formatTime(half['timeOut'] as Timestamp?)} out',
                          _darkText,
                        ),
                        const Divider(height: 20, color: StudentUi.line),
                      ],
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
