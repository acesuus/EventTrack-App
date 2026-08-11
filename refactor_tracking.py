import sys

new_content = """import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'attendance_policy.dart';
import 'geofencing_service.dart';

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

  double get _eventRadius => (widget.eventData['radius'] as num?)?.toDouble() ?? 50.0;
  
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
    _checkAndLogLocation();
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
  
  String get _eventType => widget.eventData['eventType']?.toString() ?? AttendancePolicy.eventTypeContinuous;

  LatLng? get _studentPoint => _currentPosition == null
      ? null
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  LocationSettings _buildLocationSettings() {
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  Future<void> _checkAndLogLocation() async {
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
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _buildLocationSettings(),
      );

      final distanceInMeters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _eventPoint.latitude,
        _eventPoint.longitude,
      );
      final currentlyInside = await GeofencingService.isStudentInsideEvent(
        pos, 
        widget.eventData, 
        useMock: false
      );

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
                'We detected the use of a mock location app or GPS spoofer. You cannot check into this event using fake coordinates.\\n\\nPlease disable the spoofer and rejoin the event.',
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
      await _processAttendanceLogic(currentlyInside, now);

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

  Future<void> _processAttendanceLogic(bool currentlyInside, Timestamp now) async {
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
      // Type 1: Time In / Time Out
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
          updated = true;
        }
      } else {
        if (currentlyInside) {
          // Verify checkout
          timeOut = now;
          data['timeOut'] = timeOut;
          data['status'] = currentStatus; // keeps initial status
          updated = true;
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Time Out logged successfully! Attendance Finalized.')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You must be inside the venue to Time Out.'), backgroundColor: Colors.red),
            );
          }
        }
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
            final minsGone = now.toDate().difference(lastVerified.toDate()).inMinutes;
            if (minsGone > 20) {
              currentStatus = 'Partial';
              data['status'] = currentStatus;
              updated = true;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You have been outside for over 20 mins. Status changed to Partial.'), backgroundColor: Colors.orange),
                );
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Warning: You are outside the venue. Return within ${20 - minsGone} mins to avoid penalty.')),
                );
              }
            }
          }
        }
      }
    }

    if (updated) {
      data['studentId'] = widget.studentId;
      data['eventId'] = widget.eventId;
      data['eventTitle'] = _eventTitle;
      data['eventType'] = _eventType;
      await _attendanceRef.set(data, SetOptions(merge: true));
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
      _currentStatus = currentlyInside ? 'Inside Event Area' : 'Outside Event Area';
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
    if (_isCheckingLocation) return 'Searching Location...';
    if (_attendanceStatus != null) {
      return _displayAttendanceStatus(_attendanceStatus!);
    }
    return _isInside ? 'Inside Event Area' : 'Outside Event Area';
  }

  String get _statusSubtitle {
    if (_attendanceFinalized) {
      return 'Attendance saved as ${_attendanceStatus != null ? _displayAttendanceStatus(_attendanceStatus!) : 'Recorded'}.';
    }
    if (_locationError != null) {
      return 'Location is needed to validate attendance';
    }
    if (_attendanceStatus == null) {
      return 'Tap Refresh to check in when inside the geofence.';
    }
    
    if (_eventType == AttendancePolicy.eventTypeInOut) {
      return 'You are checked in. Tap Refresh when you are ready to Time Out before leaving.';
    } else {
      if (!_isInside) {
        return 'You are outside the event area. Return within the grace period to avoid Partial status.';
      }
      return 'Your attendance is active. Tap Refresh occasionally to verify you are still inside.';
    }
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Event Tracking',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _eventType == AttendancePolicy.eventTypeInOut ? 'Time In / Time Out' : 'Continuous Stay Mode',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _statusSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _darkText, fontSize: 14),
                    ),
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
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isCheckingLocation || _attendanceFinalized ? null : _checkAndLogLocation,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: Text(
                        _isCheckingLocation ? 'Checking...' : 'Refresh / Verify Location',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
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
"""

with open('lib/event_tracking_screen.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)

print("SUCCESS")
