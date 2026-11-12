import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PointsLedgerScreen extends StatefulWidget {
  final String studentId;

  const PointsLedgerScreen({super.key, required this.studentId});

  @override
  State<PointsLedgerScreen> createState() => _PointsLedgerScreenState();
}

class _PointsLedgerScreenState extends State<PointsLedgerScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);
  final Color _goldColor = const Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      appBar: AppBar(
        title: const Text('My Points Ledger'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildTotalPointsHeader(),
          Expanded(
            child: _buildAuditList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalPointsHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: _primaryGreen,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(widget.studentId).snapshots(),
        builder: (context, snapshot) {
          int totalPoints = 0;
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            totalPoints = (data['totalPoints'] as num?)?.toInt() ?? 0;
          }

          return Column(
            children: [
              Icon(Icons.star_rounded, color: _goldColor, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Total Points Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                totalPoints.toString(),
                style: TextStyle(
                  color: _goldColor,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(
                      offset: Offset(0, 2),
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAuditList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('points_audit')
          .where('studentId', isEqualTo: widget.studentId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final eventTitle = data['eventTitle']?.toString() ?? 'Unknown Event';
            final pointsAwarded = (data['pointsAwarded'] as num?)?.toInt() ?? 0;
            final reason = data['reason']?.toString() ?? 'No reason provided';
            final timestamp = data['timestamp'] as Timestamp?;

            String dateStr = '--';
            if (timestamp != null) {
              dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp.toDate());
            }

            final isPositive = pointsAwarded > 0;
            final pointsText = isPositive ? '+$pointsAwarded' : '$pointsAwarded';
            final pointsColor = isPositive ? Colors.green.shade700 : Colors.red.shade700;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              shadowColor: Colors.black12,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: pointsColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    color: pointsColor,
                  ),
                ),
                title: Text(
                  eventTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _darkText,
                    fontSize: 16,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reason, style: TextStyle(color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                trailing: Text(
                  pointsText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pointsColor,
                    fontSize: 20,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No points earned yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check into events to start earning points!',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
