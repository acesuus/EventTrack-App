import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'widgets/student_ui.dart';

/// Shows a student exactly what EventTrack stores about them.
class PrivacyDashboardScreen extends StatelessWidget {
  const PrivacyDashboardScreen({super.key, required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudentUi.background,
      appBar: AppBar(
        title: const Text('Your data'),
        backgroundColor: StudentUi.green,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _InfoCard(
            icon: Icons.location_on_outlined,
            title: 'Location stays on your phone',
            description:
                'GPS is only used to check whether you are inside the event area. Your coordinates are never uploaded; only your attendance result is saved.',
          ),
          const _InfoCard(
            icon: Icons.timer_outlined,
            title: 'Only during events',
            description:
                'Location is checked only while you are tracking a joined event. A notification shows while this is running, and it stops when the event ends.',
          ),
          const _InfoCard(
            icon: Icons.phonelink_lock_outlined,
            title: 'One phone per account',
            description:
                'Your account is linked to a random ID created when the app was installed, to stop proxy attendance. It is not your phone number or IMEI.',
          ),
          const SizedBox(height: 12),
          const Text(
            'What is saved for each event',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: StudentUi.ink,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('attendance')
                .where('studentId', isEqualTo: studentId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  "Couldn't load your records. Check your internet connection.",
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text(
                  'Nothing yet. Records appear after you check in to an event.',
                  style: TextStyle(color: StudentUi.muted),
                );
              }
              return Column(
                children: [for (final doc in docs) _RecordCard(doc.data())],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: StudentSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: StudentUi.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: StudentUi.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: StudentUi.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard(this.data);

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('MMM d, h:mm a');
    String time(String key) {
      final value = data[key];
      return value is Timestamp ? format.format(value.toDate()) : '—';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StudentSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (data['eventTitle'] ?? data['eventName'] ?? 'Event').toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: StudentUi.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Time in: ${time('timeIn')} · Time out: ${time('timeOut')}\n'
              'Status: ${data['status'] ?? '—'} · Points: ${data['pointsAwarded'] ?? 0}\n'
              'Location coordinates: not stored',
              style: const TextStyle(color: StudentUi.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
