import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'campus_locations.dart';
import 'attendance_policy.dart';

class CreateEventScreen extends StatefulWidget {
  final String? eventId; // If null, we are Creating. If it has an ID, we are Editing.
  final Map<String, dynamic>? existingData;
  final DateTime? preSelectedDate;

  const CreateEventScreen({super.key, this.eventId, this.existingData, this.preSelectedDate});

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
  String _eventType = AttendancePolicy.eventTypeContinuous;
  String _continuousRequirement = 'Both (Time In & Out)';
  String _morningRequirement = 'Both (Time In & Out)';
  String _afternoonRequirement = 'Both (Time In & Out)';
  final TextEditingController _pointsController = TextEditingController(text: '10');
  
  // Geofence Data
  LatLng? _selectedLocation;
  PSUCampus? _selectedCampusLocation;
  final MapController _mapController = MapController();

  // Date & Time Data
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;

  DateTime? _singleEventDate;
  TimeOfDay? _morningIn;
  TimeOfDay? _morningOut;
  TimeOfDay? _afternoonIn;
  TimeOfDay? _afternoonOut;

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
      _eventType = data['eventType'] ?? AttendancePolicy.eventTypeContinuous;
      _continuousRequirement = data['continuousRequirement'] ?? data['attendanceRequirement'] ?? 'Both (Time In & Out)';
      _morningRequirement = data['morningRequirement'] ?? 'Both (Time In & Out)';
      _afternoonRequirement = data['afternoonRequirement'] ?? 'Both (Time In & Out)';
    } else if (!_isEditing && widget.preSelectedDate != null) {
      _startDate = widget.preSelectedDate;
      _endDate = widget.preSelectedDate;
    }
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _mapController.dispose();
    super.dispose();
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

  Future<void> _selectSingleDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _singleEventDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: _primaryGreen)), child: child!);
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _singleEventDate = picked;
      });
    }
  }

  Future<void> _selectSpecificTime(String session, bool isIn) async {
    TimeOfDay initialTime = TimeOfDay.now();
    if (session == 'morning') {
      initialTime = (isIn ? _morningIn : _morningOut) ?? const TimeOfDay(hour: 8, minute: 0);
    } else if (session == 'afternoon') {
      initialTime = (isIn ? _afternoonIn : _afternoonOut) ?? const TimeOfDay(hour: 13, minute: 0);
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: _primaryGreen)), child: child!);
      },
    );

    if (picked != null && mounted) {
      setState(() {
        if (session == 'morning') {
          if (isIn) _morningIn = picked;
          else _morningOut = picked;
        } else if (session == 'afternoon') {
          if (isIn) _afternoonIn = picked;
          else _afternoonOut = picked;
        }
      });
    }
  }

  // Save/Update logic
  Future<void> _saveEvent() async {
    if (_eventType == AttendancePolicy.eventTypeInOut || _eventType == 'type1_in_out') {
      if (_eventName.isEmpty || _venueName.isEmpty || _selectedLocation == null || _singleEventDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields (*)!')));
        return;
      }
      if ((_morningRequirement == 'Both (Time In & Out)' || _morningRequirement == 'Time In Only') && _morningIn == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify Morning Time In!')));
        return;
      }
      if ((_morningRequirement == 'Both (Time In & Out)' || _morningRequirement == 'Time Out Only') && _morningOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify Morning Time Out!')));
        return;
      }
      if ((_afternoonRequirement == 'Both (Time In & Out)' || _afternoonRequirement == 'Time In Only') && _afternoonIn == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify Afternoon Time In!')));
        return;
      }
      if ((_afternoonRequirement == 'Both (Time In & Out)' || _afternoonRequirement == 'Time Out Only') && _afternoonOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify Afternoon Time Out!')));
        return;
      }
    } else {
      if (_eventName.isEmpty || _venueName.isEmpty || _selectedLocation == null || _startDate == null || _endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields (*)!')));
        return;
      }
      if ((_continuousRequirement == 'Both (Time In & Out)' || _continuousRequirement == 'Time In Only') && _startTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify Start Time!')));
        return;
      }
      // Assuming we always need End Time to know when event officially closes, even if Time In Only.
      if (_endTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify End Time!')));
        return;
      }
    }

    // 1. Prepare the container for our Firestore-ready points
    List<Map<String, double>> finalPolygonPoints = [];

    if (_selectedCampusLocation != null) {
      // PRIORITY 1: The actively selected campus from the dropdown
      finalPolygonPoints = _selectedCampusLocation!.polygonPoints
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
    } else if (widget.existingData != null && widget.existingData!['polygonPoints'] != null) {
      // PRIORITY 2: Fallback to existing data (Useful when editing an event)
      final rawPoints = widget.existingData!['polygonPoints'] as List<dynamic>;
      finalPolygonPoints = rawPoints.map((point) {
        final p = Map<String, dynamic>.from(point);
        return {
          'lat': (p['lat'] as num).toDouble(),
          'lng': (p['lng'] as num).toDouble(),
        };
      }).toList();
    } else if (_selectedLocation != null) {
      // PRIORITY 3: Proximity matching if they tapped the map without using the dropdown
      const distanceCalc = Distance();
      for (final campus in PSUCampus.locations) {
        final dist = distanceCalc.distance(
          _selectedLocation!,
          LatLng(campus.latitude, campus.longitude),
        );
        if (dist <= 150.0) { // Find campuses within 150 meters
          finalPolygonPoints = campus.polygonPoints.map((point) {
            return {'lat': point.latitude, 'lng': point.longitude};
          }).toList();
          break;
        }
      }
    }

    if (finalPolygonPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to determine location boundary. Please re-select the campus venue.')),
      );
      return;
    }

    Map<String, dynamic> eventPayload = {
      'title': _eventName,
      'description': _description,
      'venueName': _venueName,
      'venueAddress': _venueAddress,
      'lat': _selectedLocation!.latitude,
      'lng': _selectedLocation!.longitude,
      'polygonPoints': finalPolygonPoints,
      'lateCutoffMinutes': _lateCutoff,
      'eventType': _eventType,
      'basePoints': int.tryParse(_pointsController.text.trim()) ?? 10,
    };

    if (_eventType == AttendancePolicy.eventTypeInOut || _eventType == 'type1_in_out') {
      eventPayload['morningRequirement'] = _morningRequirement;
      eventPayload['afternoonRequirement'] = _afternoonRequirement;
      
      Timestamp? mInTs, mOutTs, aInTs, aOutTs;
      
      if (_morningIn != null) {
        mInTs = Timestamp.fromDate(DateTime(_singleEventDate!.year, _singleEventDate!.month, _singleEventDate!.day, _morningIn!.hour, _morningIn!.minute));
        eventPayload['morningStartTime'] = mInTs;
      }
      if (_morningOut != null) {
        mOutTs = Timestamp.fromDate(DateTime(_singleEventDate!.year, _singleEventDate!.month, _singleEventDate!.day, _morningOut!.hour, _morningOut!.minute));
        eventPayload['morningEndTime'] = mOutTs;
      }
      if (_afternoonIn != null) {
        aInTs = Timestamp.fromDate(DateTime(_singleEventDate!.year, _singleEventDate!.month, _singleEventDate!.day, _afternoonIn!.hour, _afternoonIn!.minute));
        eventPayload['afternoonStartTime'] = aInTs;
      }
      if (_afternoonOut != null) {
        aOutTs = Timestamp.fromDate(DateTime(_singleEventDate!.year, _singleEventDate!.month, _singleEventDate!.day, _afternoonOut!.hour, _afternoonOut!.minute));
        eventPayload['afternoonEndTime'] = aOutTs;
      }

      eventPayload['startTime'] = mInTs ?? mOutTs ?? aInTs ?? aOutTs;
      eventPayload['endTime'] = aOutTs ?? aInTs ?? mOutTs ?? mInTs;
    } else {
      eventPayload['continuousRequirement'] = _continuousRequirement;
      
      if (_startTime != null) {
        final startDateTime = DateTime(_startDate!.year, _startDate!.month, _startDate!.day, _startTime!.hour, _startTime!.minute);
        eventPayload['startTime'] = Timestamp.fromDate(startDateTime);
      }
      if (_endTime != null) {
        final endDateTime = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, _endTime!.hour, _endTime!.minute);
        eventPayload['endTime'] = Timestamp.fromDate(endDateTime);
      }
    }

    try {

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
          content: Text(_isEditing ? 'Event "$_eventName" Updated Live!' : 'Event "$_eventName" Created Live!'), 
          backgroundColor: _primaryGreen
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint("Error saving event: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save event: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
        const SizedBox(height: 16),
        const Text('Base Event Points *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _pointsController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'e.g., 10',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryGreen, width: 2)),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Required';
            final pts = int.tryParse(value);
            if (pts == null || pts <= 0) return 'Must be > 0';
            return null;
          },
        ),
        const SizedBox(height: 16),
        const Text('Event Format *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _eventType,
              items: const [
                DropdownMenuItem(value: AttendancePolicy.eventTypeContinuous, child: Text('Continuous Stay (Type 2)')),
                DropdownMenuItem(value: AttendancePolicy.eventTypeInOut, child: Text('Time In / Time Out (Type 1)')),
              ],
              onChanged: (newValue) {
                if (newValue != null && mounted) {
                  setState(() {
                    _eventType = newValue;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard() {
    LatLng initialCenter = _selectedLocation ?? LatLng(9.778936, 118.732841);

    return _buildCard(
      title: 'Location',
      icon: Icons.location_on_outlined,
      children: [
        const Text('Campus Venue *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<PSUCampus>(
              isExpanded: true,
              hint: const Text('Select a campus building...'),
              value: _selectedCampusLocation,
              items: PSUCampus.locations.map((loc) {
                return DropdownMenuItem(value: loc, child: Text(loc.name));
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedCampusLocation = newValue;
                    _venueName = newValue.name; // Automatically set the Venue Name
                    _selectedLocation = LatLng(newValue.latitude, newValue.longitude);
                  });
                  _mapController.move(_selectedLocation!, 18.0);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildTextField('Additional Details (Optional)', 'e.g., Room 204 or Main Court', _venueAddress, (val) => _venueAddress = val),
        const SizedBox(height: 16),

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
                initialZoom: 18.0,
                minZoom: 10.0,
                maxZoom: 19.0,
                cameraConstraint: const CameraConstraint.unconstrained(),
                onTap: (tapPosition, point) {
                  setState(() {
                    _selectedLocation = point;
                  });
                },
              ),  
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.eventtrack.app'),
                if (_selectedCampusLocation != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _selectedCampusLocation!.polygonPoints,
                        color: _primaryGreen.withValues(alpha: 0.2),
                        borderColor: _primaryGreen,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementDropdown(String value, Function(String?) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: const [
            DropdownMenuItem(value: 'Both (Time In & Out)', child: Text('Requirement: Both (Time In & Out)', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'Time In Only', child: Text('Requirement: Time In Only', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'Time Out Only', child: Text('Requirement: Time Out Only', style: TextStyle(fontSize: 13))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateTimeCard() {
    return _buildCard(
      title: 'Date & Time',
      icon: Icons.access_time,
      children: [
        if (_eventType == AttendancePolicy.eventTypeContinuous || _eventType == 'type2_continuous') ...[
          _buildRequirementDropdown(_continuousRequirement, (val) => setState(() => _continuousRequirement = val ?? 'Both (Time In & Out)')),
          Row(
            children: [
              Expanded(child: _buildPickerField('Start Date *', _startDate == null ? 'dd/mm/yyyy' : DateFormat('dd/MM/yyyy').format(_startDate!), () => _selectDate(true))),
              const SizedBox(width: 16),
              if (_continuousRequirement != 'Time Out Only')
                Expanded(child: _buildPickerField('Start Time *', _startTime == null ? '--:-- --' : _startTime!.format(context), () => _selectTime(true)))
              else
                const Spacer(),
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
        ] else ...[
          _buildPickerField('Event Date *', _singleEventDate == null ? 'dd/mm/yyyy' : DateFormat('dd/MM/yyyy').format(_singleEventDate!), () => _selectSingleDate()),
          const SizedBox(height: 16),
          const Text('Morning Session', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildRequirementDropdown(_morningRequirement, (val) => setState(() => _morningRequirement = val ?? 'Both (Time In & Out)')),
          Row(
            children: [
              if (_morningRequirement != 'Time Out Only')
                Expanded(child: _buildPickerField('Morning Time In *', _morningIn == null ? '--:-- --' : _morningIn!.format(context), () => _selectSpecificTime('morning', true)))
              else
                const Spacer(),
              const SizedBox(width: 16),
              if (_morningRequirement != 'Time In Only')
                Expanded(child: _buildPickerField('Morning Time Out *', _morningOut == null ? '--:-- --' : _morningOut!.format(context), () => _selectSpecificTime('morning', false)))
              else
                const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Afternoon Session', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildRequirementDropdown(_afternoonRequirement, (val) => setState(() => _afternoonRequirement = val ?? 'Both (Time In & Out)')),
          Row(
            children: [
              if (_afternoonRequirement != 'Time Out Only')
                Expanded(child: _buildPickerField('Afternoon Time In *', _afternoonIn == null ? '--:-- --' : _afternoonIn!.format(context), () => _selectSpecificTime('afternoon', true)))
              else
                const Spacer(),
              const SizedBox(width: 16),
              if (_afternoonRequirement != 'Time In Only')
                Expanded(child: _buildPickerField('Afternoon Time Out *', _afternoonOut == null ? '--:-- --' : _afternoonOut!.format(context), () => _selectSpecificTime('afternoon', false)))
              else
                const Spacer(),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Late Cutoff (minutes after start) *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _lateCutoff,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryGreen, width: 2)),
              ),
              items: const [
                DropdownMenuItem(value: 10, child: Text('10 minutes')),
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
                DropdownMenuItem(value: 60, child: Text('60 minutes')),
              ],
              onChanged: (newValue) {
                if (newValue != null && mounted) {
                  setState(() {
                    _lateCutoff = newValue;
                  });
                }
              },
              icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
              style: TextStyle(color: _darkText, fontSize: 14),
            ),
          ],
        ),
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