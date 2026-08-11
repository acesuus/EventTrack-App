import sys
import re

with open('lib/student_dashboard.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Replace _buildSelectedTab()
old_build_selected = """  Widget _buildSelectedTab() {
    switch (_selectedIndex) {
      case 1:
        return _buildHistoryTab();
      case 2:
        return _buildSettingsTab();
      case 0:
      default:
        return _buildHomeTab();
    }
  }"""

new_build_selected = """  Widget _buildSelectedTab() {
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
            stream: _firestore.collection('events').orderBy('startTime').snapshots(),
            builder: (context, snapshot) {
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
                      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
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
                          DateTime eventDate = (data['startTime'] as Timestamp).toDate();
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
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filteredEvents.length,
                            itemBuilder: (context, index) {
                              final doc = filteredEvents[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final windowInfo = _getEventWindowInfo(data, DateTime.now());
                              return _buildEventCard(
                                doc.id,
                                data,
                                windowInfo,
                              );
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
  }"""

# 2. Replace _buildBottomNav()
old_bottom_nav = """  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      selectedItemColor: _primaryGreen,
      unselectedItemColor: Colors.grey,
      onTap: (index) => setState(() => _selectedIndex = index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          label: 'Settings',
        ),
      ],
    );
  }"""

new_bottom_nav = """  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      selectedItemColor: _primaryGreen,
      unselectedItemColor: Colors.grey,
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
  }"""

# 3. Update index hardcodes
old_settings_icon = """              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                onPressed: () => setState(() => _selectedIndex = 2),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),"""
new_settings_icon = """              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                onPressed: () => setState(() => _selectedIndex = 3),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),"""

old_history_icon = """            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => setState(() => _selectedIndex = 1),
          ),"""
new_history_icon = """            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => setState(() => _selectedIndex = 2),
          ),"""

# 4. Strip Calendar out of _buildEventsSection()
events_section_pattern = re.compile(r'  Widget _buildEventsSection\(\) \{.*?(?=  Widget _buildEventCard\()', re.DOTALL)

new_events_section = """  Widget _buildEventsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('events').orderBy('startTime').snapshots(),
      builder: (context, snapshot) {
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
                style: TextStyle(color: Colors.grey),
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
                style: TextStyle(color: Colors.grey),
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

"""

if old_build_selected not in content:
    print("FAILED TO FIND old_build_selected")
if old_bottom_nav not in content:
    print("FAILED TO FIND old_bottom_nav")

content = content.replace(old_build_selected, new_build_selected)
content = content.replace(old_bottom_nav, new_bottom_nav)
content = content.replace(old_settings_icon, new_settings_icon)
content = content.replace(old_history_icon, new_history_icon)

content = events_section_pattern.sub(new_events_section, content)

with open('lib/student_dashboard.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("SUCCESS")
