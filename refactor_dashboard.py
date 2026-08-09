import sys
import re

with open('lib/student_dashboard.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update _buildHomeTab
home_tab_old = """  Widget _buildHomeTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _buildHomeHeader(),
              const SizedBox(height: 20),
              _buildEventsSection(),
              const SizedBox(height: 20),
              _buildQuickActions(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    );
  }"""
home_tab_new = """  Widget _buildHomeTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _buildHomeHeader(),
              const SizedBox(height: 20),
              _buildPointsCard(),
              const SizedBox(height: 20),
              _buildEventsSection(),
              const SizedBox(height: 20),
              _buildQuickActions(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPointsCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('attendance')
          .where('studentId', isEqualTo: widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        int totalPoints = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status']?.toString() ?? 'Absent';
            totalPoints += AttendancePolicy.getPointsForStatus(status);
          }
        }
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryGreen, Colors.green.shade700],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _primaryGreen.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stars, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CS Association Points',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalPoints pts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }"""
content = content.replace(home_tab_old, home_tab_new)

# 2. Update _buildHistoryCard
history_card_old = """          if (hasSessionData)
            _buildHistoryRow('Time Away', _formatDuration(totalOutsideSeconds)),
        ],
      ),
    );
  }"""
history_card_new = """          if (hasSessionData)
            _buildHistoryRow('Time Away', _formatDuration(totalOutsideSeconds)),
          _buildHistoryRow('Points Earned', '${AttendancePolicy.getPointsForStatus(status)} pts'),
        ],
      ),
    );
  }"""
content = content.replace(history_card_old, history_card_new)

with open('lib/student_dashboard.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("SUCCESS")
