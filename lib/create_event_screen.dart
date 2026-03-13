import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CreateEventScreen extends StatefulWidget {
  final String? eventId; // If null, we are Creating. If it has an ID, we are Editing.
  final Map<String, dynamic>? existingData;

  const CreateEventScreen({super.key, this.eventId, this.existingData});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Theme Colors
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  // Form Data
  String _eventName = "";
  String _description = "";
  String _venueName = "";
  String _venueAddress = "";
  int _lateCutoff = 15;
  
  // Geofence Data
  LatLng? _selectedLocation;
  double _currentRadius = 100.0;
  final MapController _mapController = MapController();

  // Date & Time Data
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;

  bool get _isEditing => widget.eventId != null;

  @override
  void initState() {
    super.initState();
    // If we passed existing data, pre-fill all the variables!
    if (_isEditing && widget.existingData != null) {
      final data = widget.existingData!;
      _eventName = data['title'] ?? '';
      _description = data['description'] ?? '';
      _venueName = data['venueName'] ?? '';
      _venueAddress = data['venueAddress'] ?? '';
      _lateCutoff = data['lateCutoffMinutes'] ?? 15;
      _currentRadius = (data['radius'] as num?)?.toDouble() ?? 100.0;

      if (data['lat'] != null && data['lng'] != null) {
        _selectedLocation = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
      }

      if (data['startTime'] != null) {
        DateTime start = (data['startTime'] as Timestamp).toDate();
        _startDate = start;
        _startTime = TimeOfDay.fromDateTime(start);
      }

      if (data['endTime'] != null) {
        DateTime end = (data['endTime'] as Timestamp).toDate();
        _endDate = end;
        _endTime = TimeOfDay.fromDateTime(end);
      }
    }
  }

  // Helper for Pickers
  Future<void> _selectDate(bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2020), // Allow past dates for editing old events
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: _primaryGreen)), child: child!);
      },
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: _primaryGreen)), child: child!);
      },
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  // Save/Update logic
  Future<void> _saveEvent() async {
    if (_eventName.isEmpty || _venueName.isEmpty || _selectedLocation == null || 
        _startDate == null || _startTime == null || _endDate == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields (*) and select a location on the map!')),
      );
      return;
    }

    final startDateTime = DateTime(_startDate!.year, _startDate!.month, _startDate!.day, _startTime!.hour, _startTime!.minute);
    final endDateTime = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, _endTime!.hour, _endTime!.minute);

    try {
      final eventPayload = {
        'title': _eventName,
        'description': _description,
        'venueName': _venueName,
        'venueAddress': _venueAddress,
        'lat': _selectedLocation!.latitude,
        'lng': _selectedLocation!.longitude,
        'radius': _currentRadius,
        'startTime': Timestamp.fromDate(startDateTime),
        'endTime': Timestamp.fromDate(endDateTime),
        'lateCutoffMinutes': _lateCutoff,
      };

      if (_isEditing) {
        // UPDATE EXISTING
        await _firestore.collection('events').doc(widget.eventId).update(eventPayload);
      } else {
        // CREATE NEW
        eventPayload['createdAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('events').add(eventPayload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Event "$_eventName" Updated!' : 'Event "$_eventName" Created!'), 
          backgroundColor: _primaryGreen
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint("Error saving event: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      appBar: AppBar(
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEditing ? 'Edit Event' : 'Create New Event', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const Text('Fill in event information', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildBasicInfoCard(),
                  const SizedBox(height: 16),
                  _buildLocationCard(),
                  const SizedBox(height: 16),
                  _buildDateTimeCard(),
                ],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primaryGreen, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String hint, String initialValue, Function(String) onChanged, {int maxLines = 1, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: initialValue,
            maxLines: maxLines,
            keyboardType: type,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryGreen, width: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return _buildCard(
      title: 'Basic Information',
      icon: Icons.calendar_today_outlined,
      children: [
        _buildTextField('Event Name *', 'e.g., Student Orientation', _eventName, (val) => _eventName = val),
        _buildTextField('Description', 'Brief description of the event', _description, (val) => _description = val, maxLines: 3),
      ],
    );
  }

  Widget _buildLocationCard() {
    LatLng initialCenter = _selectedLocation ?? const LatLng(9.7389, 118.7353);

    return _buildCard(
      title: 'Location & Geofence',
      icon: Icons.location_on_outlined,
      children: [
        _buildTextField('Venue Name *', 'e.g., PSU Main Auditorium', _venueName, (val) => _venueName = val),
        _buildTextField('Venue Address', 'Full address', _venueAddress, (val) => _venueAddress = val),
        
        const Text('Tap the map to set Geofence Center *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          height: 200,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 16.0,
                onTap: (tapPosition, point) => setState(() => _selectedLocation = point),
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.eventtrack.app'),
                if (_selectedLocation != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _selectedLocation!,
                        color: _primaryGreen.withValues(alpha: 0.2),
                        borderColor: _primaryGreen,
                        borderStrokeWidth: 2,
                        useRadiusInMeter: true,
                        radius: _currentRadius,
                      ),
                    ],
                  ),
                if (_selectedLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(point: _selectedLocation!, width: 40, height: 40, child: Icon(Icons.location_pin, color: _primaryGreen, size: 40)),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        _buildTextField('Geofence Radius (meters) *', '100', _currentRadius.toString(), (val) {
          setState(() { _currentRadius = double.tryParse(val) ?? 100.0; });
        }, type: TextInputType.number),
        const Text('Typical range: 50-200 meters. Use 5000m for testing.', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildDateTimeCard() {
    return _buildCard(
      title: 'Date & Time',
      icon: Icons.access_time,
      children: [
        Row(
          children: [
            Expanded(child: _buildPickerField('Start Date *', _startDate == null ? 'dd/mm/yyyy' : DateFormat('dd/MM/yyyy').format(_startDate!), () => _selectDate(true))),
            const SizedBox(width: 16),
            Expanded(child: _buildPickerField('Start Time *', _startTime == null ? '--:-- --' : _startTime!.format(context), () => _selectTime(true))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildPickerField('End Date *', _endDate == null ? 'dd/mm/yyyy' : DateFormat('dd/MM/yyyy').format(_endDate!), () => _selectDate(false))),
            const SizedBox(width: 16),
            Expanded(child: _buildPickerField('End Time *', _endTime == null ? '--:-- --' : _endTime!.format(context), () => _selectTime(false))),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField('Late Cutoff (minutes after start) *', '15', _lateCutoff.toString(), (val) => _lateCutoff = int.tryParse(val) ?? 15, type: TextInputType.number),
      ],
    );
  }

  Widget _buildPickerField(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(value, style: TextStyle(color: value.contains('-') || value.contains('y') ? Colors.grey.shade500 : Colors.black, fontSize: 14))],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 12),
      decoration: BoxDecoration(color: _lightGreenBg, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Colors.grey.shade300),
                  backgroundColor: Colors.grey.shade200,
                ),
                child: const Text('Cancel', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveEvent,
                icon: Icon(_isEditing ? Icons.update : Icons.save_outlined, color: Colors.white),
                label: Text(_isEditing ? 'Update Event' : 'Create Event', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}