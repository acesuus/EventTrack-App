import sys
import re

with open('lib/create_event_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import
if "import 'attendance_policy.dart';" not in content:
    content = content.replace("import 'campus_locations.dart';", "import 'campus_locations.dart';\nimport 'attendance_policy.dart';")

# 2. Add state variable
if "String _eventType" not in content:
    content = content.replace('int _lateCutoff = 15;', "int _lateCutoff = 15;\n  String _eventType = AttendancePolicy.eventTypeContinuous;")

# 3. Add to init state
init_state_replace = """      if (data['endTime'] != null) {
        DateTime end = (data['endTime'] as Timestamp).toDate();
        _endDate = end;
        _endTime = TimeOfDay.fromDateTime(end);
      }"""
init_state_new = """      if (data['endTime'] != null) {
        DateTime end = (data['endTime'] as Timestamp).toDate();
        _endDate = end;
        _endTime = TimeOfDay.fromDateTime(end);
      }
      _eventType = data['eventType'] ?? AttendancePolicy.eventTypeContinuous;"""
content = content.replace(init_state_replace, init_state_new)

# 4. Add to payload
payload_replace = """        'endTime': Timestamp.fromDate(endDateTime),
        'lateCutoffMinutes': _lateCutoff,"""
payload_new = """        'endTime': Timestamp.fromDate(endDateTime),
        'lateCutoffMinutes': _lateCutoff,
        'eventType': _eventType,"""
content = content.replace(payload_replace, payload_new)

# 5. Add to UI (Basic Info Card)
basic_info_replace = """  Widget _buildBasicInfoCard() {
    return _buildCard(
      title: 'Basic Information',
      icon: Icons.calendar_today_outlined,
      children: [
        _buildTextField('Event Name *', 'e.g., Student Orientation', _eventName, (val) => _eventName = val),
        _buildTextField('Description', 'Brief description of the event', _description, (val) => _description = val, maxLines: 3),
      ],
    );
  }"""
basic_info_new = """  Widget _buildBasicInfoCard() {
    return _buildCard(
      title: 'Basic Information',
      icon: Icons.calendar_today_outlined,
      children: [
        _buildTextField('Event Name *', 'e.g., Student Orientation', _eventName, (val) => _eventName = val),
        _buildTextField('Description', 'Brief description of the event', _description, (val) => _description = val, maxLines: 3),
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
  }"""
content = content.replace(basic_info_replace, basic_info_new)

with open('lib/create_event_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("SUCCESS")
