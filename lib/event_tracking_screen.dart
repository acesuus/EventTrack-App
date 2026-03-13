import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  Timer? _locationTimer;
  bool _isInside = false;
  Timestamp? _timeIn;
  String _currentStatus = "Loading...";

  @override
  void initState() {
    super.initState();
    _startLocationPolling();
  }

  @override
  void dispose() {
    _locationTimer?.cancel(); 
    super.dispose();
  }

  Future<void> _startLocationPolling() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    await _checkAndLogLocation();

    _locationTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _checkAndLogLocation();
    });
  }

Future<void> _checkAndLogLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      
      // 🚨 ANTI-FRAUD: THE SPOOFING BLOCK 🚨
      // Check if the GPS coordinates are coming from a "Fake Location" app
      if (pos.isMocked) {
        setState(() {
          _isInside = false;
          _currentStatus = "Spoofing Detected";
        });
        
        // Stop the timer so they can't keep pinging fake locations
        _locationTimer?.cancel();
        
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false, // Force them to click OK
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Invalid Location', style: TextStyle(color: Colors.red)),
                ],
              ),
              content: const Text('We detected the use of a mock location app or GPS spoofer. You cannot check into this event using fake coordinates.\n\nPlease disable the spoofer and rejoin the event.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Kick them out to the dashboard
                  },
                  child: const Text('Exit Event'),
                ),
              ],
            ),
          );
        }
        return; // Abort the rest of the check-in process!
      }

      // --- Normal Geofencing Logic Below ---
      double eventLat = (widget.eventData['lat'] as num).toDouble();
      double eventLng = (widget.eventData['lng'] as num).toDouble();
      double radius = (widget.eventData['radius'] as num).toDouble();

      double distanceInMeters = Geolocator.distanceBetween(pos.latitude, pos.longitude, eventLat, eventLng);
      bool currentlyInside = distanceInMeters <= radius;

      setState(() {
        _isInside = currentlyInside;
      });

      if (currentlyInside) {
        final docId = '${widget.studentId}_${widget.eventId}';
        final attendanceRef = _firestore.collection('attendance').doc(docId);
        
        final docSnap = await attendanceRef.get();
        if (!docSnap.exists) {
          DateTime eventStart = (widget.eventData['startTime'] as Timestamp).toDate();
          int lateCutoff = widget.eventData['lateCutoffMinutes'] ?? 15;
          DateTime cutoffTime = eventStart.add(Duration(minutes: lateCutoff));
          
          String initialStatus = DateTime.now().isAfter(cutoffTime) ? 'Late' : 'Present';

          final now = FieldValue.serverTimestamp();
          await attendanceRef.set({
            'studentId': widget.studentId,
            'eventId': widget.eventId,
            'eventTitle': widget.eventData['title'],
            'status': initialStatus,
            'timeIn': now,
            'timeOut': null,
          });
          
          final updatedSnap = await attendanceRef.get();
          setState(() {
            _timeIn = updatedSnap.data()?['timeIn'];
            _currentStatus = initialStatus;
          });
        } else {
          setState(() {
            _timeIn = docSnap.data()?['timeIn'];
            _currentStatus = docSnap.data()?['status'] ?? 'Present';
          });
        }
      }
    } catch (e) {
      debugPrint("Error in location polling: $e");
    }
  }

  // PHASE 4: THE "PARTIAL" CALCULATION (EXIT EVENT)
  Future<void> _exitEvent() async {
    // 1. Confirm they actually want to leave
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Event?'),
        content: const Text('If you leave before the event officially ends, your attendance will be marked as Partial. Are you sure you want to exit?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Exit', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    // 2. Stop tracking GPS
    _locationTimer?.cancel();

    // 3. Calculate Early Departure
    DateTime eventEnd = (widget.eventData['endTime'] as Timestamp).toDate();
    DateTime now = DateTime.now();
    String finalStatus = _currentStatus; 

    // Grace Period: Leaving within 15 minutes of the end time is fine.
    // If they leave earlier than that, override their status to 'Partial'.
    if (now.isBefore(eventEnd.subtract(const Duration(minutes: 15)))) {
      finalStatus = 'Partial';
    }

    // 4. Update the Database
    final docId = '${widget.studentId}_${widget.eventId}';
    await _firestore.collection('attendance').doc(docId).update({
      'timeOut': FieldValue.serverTimestamp(),
      'status': finalStatus,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Checked out. Final Status: $finalStatus'), backgroundColor: _darkText),
    );
    Navigator.pop(context); // Go back to dashboard
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "--:--";
    return DateFormat('hh:mm a').format(timestamp.toDate());
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
            Text('Event Tracking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Live monitoring active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                children: [
                  Icon(
                    _isInside ? Icons.check_circle : Icons.location_searching, 
                    color: _isInside ? _primaryGreen : Colors.orange, 
                    size: 60
                  ),
                  const SizedBox(height: 12),
                  // Dynamically show Present, Late, or Searching
              // Dynamically show Present, Late, Searching, or Spoofing
                  Text(
                    _isInside ? _currentStatus : (_currentStatus == 'Spoofing Detected' ? 'Spoofing Detected' : 'Searching Location...'), 
                    style: TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold, 
                      // Turn text RED if spoofing is detected
                      color: _currentStatus == 'Spoofing Detected' 
                          ? Colors.red 
                          : (_isInside ? (_currentStatus == 'Late' ? Colors.orange : _primaryGreen) : Colors.orange)
                    )
                  ),  
                  const SizedBox(height: 4),
                  Text('Your current attendance status', style: TextStyle(color: _darkText, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Event Info (Unchanged)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.eventData['title'] ?? '', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined, color: _primaryGreen, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.eventData['venueName'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: _darkText)),
                            Text(widget.eventData['venueAddress'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.access_time, color: _primaryGreen, size: 20),
                      const SizedBox(width: 8),
                      Text("${_formatTime(widget.eventData['startTime'])} - ${_formatTime(widget.eventData['endTime'])}", style: TextStyle(color: _darkText)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Location Radar (Unchanged)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Location Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: _isInside ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 10, color: _isInside ? _primaryGreen : Colors.orange),
                            const SizedBox(width: 6),
                            Text(_isInside ? 'Inside' : 'Outside', style: TextStyle(color: _isInside ? _primaryGreen : Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16)),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 100, width: 100,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _primaryGreen, width: 2, style: BorderStyle.solid)),
                          ),
                          Icon(Icons.location_pin, color: _primaryGreen, size: 40),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildDataRow('GPS Accuracy', 'High', _primaryGreen),
                  const Divider(),
                  _buildDataRow('Time In', _timeIn != null ? _formatTime(_timeIn) : '--:--', _darkText),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Exit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _exitEvent,
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text('Exit Event', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade500,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your location is being monitored for attendance tracking. Stay within the event area to maintain your Present status.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 11),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }
}