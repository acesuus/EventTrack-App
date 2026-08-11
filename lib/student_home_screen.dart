import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class StudentHomeScreen extends StatefulWidget {
  final String studentId;
  const StudentHomeScreen({super.key, required this.studentId});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Color _primaryGreen = const Color(0xFF28A776);
  
  StreamSubscription<Position>? _positionStream;
  String _statusMessage = "Scanning for nearby events...";
  bool _isPresent = false;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _startGeofencing();
  }

  Future<void> _toggleOfflineMode(bool value) async {
    if (value) {
      // Going Offline: Pre-load active events to the cache
      try {
        final now = Timestamp.now();
        await _firestore
            .collection('events')
            .where('startTime', isLessThanOrEqualTo: now)
            .get(const GetOptions(source: Source.server));
      } catch (e) {
        debugPrint("Pre-load fetch failed (you might already be offline): $e");
      }

      // Disconnect Firestore
      await _firestore.disableNetwork();
      
      setState(() => _isOfflineMode = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Data pre-loaded. App is now in Offline Mode."))
        );
      }
    } else {
      // Going Online: Reconnect and sync
      await _firestore.enableNetwork();
      
      setState(() => _isOfflineMode = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("App is Online. Attendance synced."))
        );
      }
    }
  }

  @override
  void dispose() {
    // PRIVACY LOCK: Kills the GPS listener the moment the screen closes
    _positionStream?.cancel();
    super.dispose();
  }

  void _startGeofencing() {
    // Listen to the student's location updating in real-time
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Only update if they move 5 meters (saves battery)
      ),
    ).listen((Position currentPos) {
      _checkAttendanceBoundary(currentPos);
    });
  }

  Future<void> _checkAttendanceBoundary(Position currentPos) async {
    final now = Timestamp.now();

    // 1. Fetch events happening RIGHT NOW (Reads from Cache if Offline)
    final activeEventsQuery = await _firestore
        .collection('events')
        .where('startTime', isLessThanOrEqualTo: now)
        // Note: Firestore requires a composite index to run two inequality operators. 
        // For now, we fetch started events and filter the end time locally.
        .get(GetOptions(source: _isOfflineMode ? Source.cache : Source.serverAndCache));

    for (var doc in activeEventsQuery.docs) {
      final data = doc.data();
      final endTime = data['endTime'] as Timestamp;

      // PRIVACY LOCK: Ignore events that have already ended
      if (now.compareTo(endTime) > 0) continue; 

      double eventLat = data['lat'];
      double eventLng = data['lng'];
      double radius = (data['radius'] as num).toDouble();

      // 2. The Math: Calculate distance
      double distanceInMeters = Geolocator.distanceBetween(
        currentPos.latitude, currentPos.longitude,
        eventLat, eventLng,
      );

      // 3. Check-In Logic
      bool isInside = distanceInMeters <= radius;

      if (isInside) {
        _logAttendance(doc.id, data['title']);
      }
    }
  }

  Future<void> _logAttendance(String eventId, String eventTitle) async {
    final docId = '${widget.studentId}_$eventId'; // Unique ID prevents double-logging
    final attendanceRef = _firestore.collection('attendance').doc(docId);

    // Avoid hanging reads when trying to check doc existence offline
    DocumentSnapshot docSnap;
    try {
      docSnap = await attendanceRef.get(GetOptions(source: _isOfflineMode ? Source.cache : Source.serverAndCache));
    } catch (_) {
      docSnap = await attendanceRef.get(const GetOptions(source: Source.cache));
    }

    if (!docSnap.exists) {
      // First time entering the circle! Check-in!
      await attendanceRef.set({
        'studentId': widget.studentId,
        'eventId': eventId,
        'eventTitle': eventTitle,
        'status': 'Present',
        'timeIn': Timestamp.now(), // Resolved locally, completes immediately offline.
        'timeOut': null,
      });

      if (mounted) {
        setState(() {
          _isPresent = true;
          _statusMessage = "You are checked into: $eventTitle";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF9F1),
      appBar: AppBar(
        title: const Text('Student ID Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          Row(
            children: [
              const Text('Offline Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Switch(
                value: _isOfflineMode,
                onChanged: _toggleOfflineMode,
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.yellow.shade700,
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_isOfflineMode)
            Container(
              width: double.infinity,
              color: Colors.yellow.shade700,
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: const Text(
                "Offline Mode: Attendance will be saved locally and synced when connected.",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Radar Animation / Status Icon
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: _isPresent ? _primaryGreen.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPresent ? Icons.check_circle : Icons.radar,
                      size: 100,
                      color: _isPresent ? _primaryGreen : Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Keep this app open while entering the venue.",
                    style: TextStyle(color: Colors.grey),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}