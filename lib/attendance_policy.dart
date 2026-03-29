import 'package:cloud_firestore/cloud_firestore.dart';

class AttendancePolicy {
  static const int schemaVersion = 2;
  static const int defaultLateCutoffMinutes = 15;
  static const int allowedOutsideSeconds = 15 * 60;

  static String determineInitialStatus({
    required DateTime checkInTime,
    required DateTime eventStart,
    int lateCutoffMinutes = defaultLateCutoffMinutes,
  }) {
    final cutoffTime = eventStart.add(Duration(minutes: lateCutoffMinutes));
    return checkInTime.isAfter(cutoffTime) ? 'Late' : 'Present';
  }

  static String determineFinalStatus({
    required String initialStatus,
    required int totalOutsideSeconds,
  }) {
    if (totalOutsideSeconds > allowedOutsideSeconds) {
      return 'Partial';
    }
    return initialStatus;
  }

  static bool isFinalizedRecord(Timestamp? timeOut) => timeOut != null;

  static bool canJoinExistingAttendance(Timestamp? timeOut) {
    return !isFinalizedRecord(timeOut);
  }

  static bool shouldAutoFinalize({
    required Timestamp? timeOut,
    required DateTime eventEnd,
    required DateTime now,
  }) {
    return timeOut == null && !eventEnd.isAfter(now);
  }
}

class AttendanceSessionRecord {
  final int schemaVersion;
  final String initialStatus;
  final String status;
  final Timestamp? timeIn;
  final Timestamp? timeOut;
  final int totalOutsideSeconds;
  final List<Map<String, dynamic>> sessions;

  const AttendanceSessionRecord({
    required this.schemaVersion,
    required this.initialStatus,
    required this.status,
    required this.timeIn,
    required this.timeOut,
    required this.totalOutsideSeconds,
    required this.sessions,
  });

  factory AttendanceSessionRecord.createInitial({
    required String initialStatus,
    required Timestamp startedAt,
  }) {
    return AttendanceSessionRecord(
      schemaVersion: AttendancePolicy.schemaVersion,
      initialStatus: initialStatus,
      status: initialStatus,
      timeIn: startedAt,
      timeOut: null,
      totalOutsideSeconds: 0,
      sessions: [
        {'timeIn': startedAt, 'timeOut': null},
      ],
    );
  }

  factory AttendanceSessionRecord.fromFirestore(Map<String, dynamic>? data) {
    final rawSessions = data?['sessions'] as List<dynamic>? ?? const [];
    final normalizedSessions = rawSessions
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          final timeIn = map['timeIn'] as Timestamp?;
          final timeOut = map['timeOut'] as Timestamp?;
          if (timeIn == null) {
            return null;
          }
          return {'timeIn': timeIn, 'timeOut': timeOut};
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final status = data?['status']?.toString() ?? 'Present';

    return AttendanceSessionRecord(
      schemaVersion: (data?['schemaVersion'] as num?)?.toInt() ?? 1,
      initialStatus: data?['initialStatus']?.toString() ?? status,
      status: status,
      timeIn: data?['timeIn'] as Timestamp?,
      timeOut: data?['timeOut'] as Timestamp?,
      totalOutsideSeconds: (data?['totalOutsideSeconds'] as num?)?.toInt() ?? 0,
      sessions: normalizedSessions,
    );
  }

  bool get isFinalized => timeOut != null;

  bool get hasOpenSession {
    if (sessions.isEmpty) return false;
    return sessions.last['timeOut'] == null;
  }

  int get returnCount => sessions.length <= 1 ? 0 : sessions.length - 1;

  bool get needsLegacyBootstrap {
    if (isFinalized) return false;
    if (sessions.isNotEmpty) return false;
    return status == 'Present' || status == 'Late';
  }

  String get currentSummaryStatus => isFinalized ? status : initialStatus;

  int displayOutsideSecondsAt(DateTime now) {
    if (isFinalized || hasOpenSession || sessions.isEmpty) {
      return totalOutsideSeconds;
    }

    final lastTimeout = sessions.last['timeOut'] as Timestamp?;
    if (lastTimeout == null) {
      return totalOutsideSeconds;
    }

    return totalOutsideSeconds +
        _positiveDiffSeconds(lastTimeout, Timestamp.fromDate(now));
  }

  AttendanceSessionRecord bootstrapLegacyIfNeeded({Timestamp? fallbackStart}) {
    if (!needsLegacyBootstrap) return this;

    final start = timeIn ?? fallbackStart ?? Timestamp.now();

    return copyWith(
      schemaVersion: AttendancePolicy.schemaVersion,
      initialStatus: status,
      timeIn: start,
      timeOut: null,
      totalOutsideSeconds: 0,
      sessions: [
        {'timeIn': start, 'timeOut': null},
      ],
    );
  }

  AttendanceSessionRecord enterGeofence(Timestamp at) {
    if (isFinalized) return this;

    var normalized = bootstrapLegacyIfNeeded(fallbackStart: at);
    if (normalized.hasOpenSession) return normalized;

    final updatedSessions = normalized._cloneSessions();
    var updatedOutsideSeconds = normalized.totalOutsideSeconds;

    if (updatedSessions.isNotEmpty) {
      final previousTimeout = updatedSessions.last['timeOut'] as Timestamp?;
      if (previousTimeout != null) {
        updatedOutsideSeconds += _positiveDiffSeconds(previousTimeout, at);
      }
    }

    updatedSessions.add({'timeIn': at, 'timeOut': null});

    return normalized.copyWith(
      schemaVersion: AttendancePolicy.schemaVersion,
      timeIn: normalized.timeIn ?? at,
      status: normalized.initialStatus,
      totalOutsideSeconds: updatedOutsideSeconds,
      sessions: updatedSessions,
    );
  }

  AttendanceSessionRecord leaveGeofence(Timestamp at) {
    if (isFinalized) return this;

    final normalized = bootstrapLegacyIfNeeded(fallbackStart: at);
    if (!normalized.hasOpenSession) return normalized;

    final updatedSessions = normalized._cloneSessions();
    final lastSession = Map<String, dynamic>.from(updatedSessions.last);
    lastSession['timeOut'] = at;
    updatedSessions[updatedSessions.length - 1] = lastSession;

    return normalized.copyWith(
      schemaVersion: AttendancePolicy.schemaVersion,
      sessions: updatedSessions,
      status: normalized.initialStatus,
    );
  }

  AttendanceSessionRecord finalize(Timestamp at) {
    if (isFinalized) return this;

    final normalized = bootstrapLegacyIfNeeded(fallbackStart: at);
    final updatedSessions = normalized._cloneSessions();
    var updatedOutsideSeconds = normalized.totalOutsideSeconds;

    if (updatedSessions.isNotEmpty) {
      final lastSession = Map<String, dynamic>.from(updatedSessions.last);
      final lastTimeOut = lastSession['timeOut'] as Timestamp?;

      if (lastTimeOut == null) {
        lastSession['timeOut'] = at;
        updatedSessions[updatedSessions.length - 1] = lastSession;
      } else {
        updatedOutsideSeconds += _positiveDiffSeconds(lastTimeOut, at);
      }
    } else {
      updatedSessions.add({'timeIn': normalized.timeIn ?? at, 'timeOut': at});
    }

    final finalStatus = AttendancePolicy.determineFinalStatus(
      initialStatus: normalized.initialStatus,
      totalOutsideSeconds: updatedOutsideSeconds,
    );

    return normalized.copyWith(
      schemaVersion: AttendancePolicy.schemaVersion,
      status: finalStatus,
      timeOut: at,
      totalOutsideSeconds: updatedOutsideSeconds,
      sessions: updatedSessions,
    );
  }

  Map<String, dynamic> toFirestoreFields({
    required String studentId,
    required String eventId,
    required String eventTitle,
  }) {
    return {
      'schemaVersion': AttendancePolicy.schemaVersion,
      'studentId': studentId,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'initialStatus': initialStatus,
      'status': status,
      'timeIn': timeIn,
      'timeOut': timeOut,
      'totalOutsideSeconds': totalOutsideSeconds,
      'sessions': sessions,
    };
  }

  AttendanceSessionRecord copyWith({
    int? schemaVersion,
    String? initialStatus,
    String? status,
    Timestamp? timeIn,
    Object? timeOut = _sentinel,
    int? totalOutsideSeconds,
    List<Map<String, dynamic>>? sessions,
  }) {
    return AttendanceSessionRecord(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      initialStatus: initialStatus ?? this.initialStatus,
      status: status ?? this.status,
      timeIn: timeIn ?? this.timeIn,
      timeOut: identical(timeOut, _sentinel)
          ? this.timeOut
          : timeOut as Timestamp?,
      totalOutsideSeconds: totalOutsideSeconds ?? this.totalOutsideSeconds,
      sessions: sessions ?? _cloneSessions(),
    );
  }

  List<Map<String, dynamic>> _cloneSessions() {
    return sessions.map((entry) => Map<String, dynamic>.from(entry)).toList();
  }

  static int _positiveDiffSeconds(Timestamp from, Timestamp to) {
    final seconds = to.toDate().difference(from.toDate()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }
}

const Object _sentinel = Object();
