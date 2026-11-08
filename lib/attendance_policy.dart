import 'package:cloud_firestore/cloud_firestore.dart';

/// One attendance window of a Time In/Out event (the morning or afternoon half).
typedef AttendanceHalf = ({DateTime start, DateTime end});

class AttendancePolicy {
  static const int schemaVersion = 4;
  static const int defaultLateCutoffMinutes = 15;
  static const int allowedOutsideSeconds = 15 * 60;
  static const int defaultCheckInOpenMinutes = 15;

  /// Check-out for a half opens this many minutes before the half ends.
  static const int checkOutOpenMinutesBeforeEnd = 15;

  /// How often an inside reading is saved while the student stays at the venue.
  static const int heartbeatSeconds = 2 * 60;

  /// After this long without a saved inside reading, the student counts as gone.
  static const int heartbeatToleranceSeconds = 5 * 60;

  static const String eventTypeInOut = 'type1_in_out';
  static const String eventTypeContinuous = 'type2_continuous';

  /// Must match expectedPoints() in firestore.rules.
  static int pointsFor(String status, int basePoints) {
    switch (status) {
      case 'Present':
        return basePoints;
      case 'Late':
      case 'Partial':
        return (basePoints / 2).round();
      default:
        return 0;
    }
  }

  /// Legacy fallback for records saved before pointsAwarded existed.
  static int getPointsForStatus(String status) => pointsFor(status, 10);

  static int basePointsOf(Map<String, dynamic> event) =>
      int.tryParse(event['basePoints']?.toString() ?? '') ?? 10;

  static int lateCutoffOf(Map<String, dynamic> event) =>
      (event['lateCutoffMinutes'] as num?)?.toInt() ?? defaultLateCutoffMinutes;

  static int checkInOpenOf(Map<String, dynamic> event) =>
      (event['checkInOpenMinutesBeforeStart'] as num?)?.toInt() ??
      defaultCheckInOpenMinutes;

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

  // ---------------------------------------------------------------------------
  // Time In/Out events: a morning and an afternoon half, each needs a check-in
  // and a check-out at the venue. Both halves = initial status, otherwise Partial.
  // ---------------------------------------------------------------------------

  /// Events created before halves existed have a single half spanning the event.
  static List<AttendanceHalf> inOutHalves(Map<String, dynamic> event) {
    DateTime? at(String key) => (event[key] as Timestamp?)?.toDate();
    final mStart = at('morningStartTime');
    final mEnd = at('morningEndTime');
    final aStart = at('afternoonStartTime');
    final aEnd = at('afternoonEndTime');
    if (mStart != null && mEnd != null && aStart != null && aEnd != null) {
      return [(start: mStart, end: mEnd), (start: aStart, end: aEnd)];
    }
    return [(start: at('startTime')!, end: at('endTime')!)];
  }

  /// The half whose window (check-in opening to its end) contains [now], or null.
  static int? halfIndexAt(
    List<AttendanceHalf> halves,
    DateTime now, {
    int checkInOpenMinutes = defaultCheckInOpenMinutes,
  }) {
    for (var i = 0; i < halves.length; i++) {
      final opens = halves[i].start.subtract(
        Duration(minutes: checkInOpenMinutes),
      );
      if (!now.isBefore(opens) && !now.isAfter(halves[i].end)) return i;
    }
    return null;
  }

  static DateTime checkOutOpensAt(AttendanceHalf half) => half.end.subtract(
    const Duration(minutes: checkOutOpenMinutesBeforeEnd),
  );

  static List<Map<String, dynamic>> halvesOf(
    Map<String, dynamic> data,
    int count,
  ) {
    final raw = data['halves'] as List<dynamic>? ?? const [];
    return List.generate(count, (i) {
      if (i < raw.length && raw[i] is Map) {
        final m = Map<String, dynamic>.from(raw[i] as Map);
        return {'timeIn': m['timeIn'], 'timeOut': m['timeOut']};
      }
      return <String, dynamic>{'timeIn': null, 'timeOut': null};
    });
  }

  static String inOutFinalStatus(Map<String, dynamic> data, int halfCount) {
    final initial = (data['initialStatus'] ?? data['status'] ?? 'Present')
        .toString();
    final complete = halvesOf(
      data,
      halfCount,
    ).where((h) => h['timeIn'] != null && h['timeOut'] != null).length;
    return complete == halfCount ? initial : 'Partial';
  }

  /// Applies one verified location to a Time In/Out record.
  /// Returns the updated record, or null when nothing changed.
  static Map<String, dynamic>? verifyInOutAttendance({
    required Map<String, dynamic> existing,
    required Timestamp verifiedAt,
    required List<AttendanceHalf> halves,
    required bool isInside,
    bool checkOutRequested = false,
    int lateCutoffMinutes = defaultLateCutoffMinutes,
    int checkInOpenMinutes = defaultCheckInOpenMinutes,
  }) {
    if (existing['timeOut'] != null || !isInside) return null;
    final now = verifiedAt.toDate();
    final index = halfIndexAt(
      halves,
      now,
      checkInOpenMinutes: checkInOpenMinutes,
    );
    if (index == null) return null;

    final data = Map<String, dynamic>.from(existing);
    final parts = halvesOf(data, halves.length);
    final part = parts[index];

    if (part['timeIn'] == null) {
      part['timeIn'] = verifiedAt;
      if (data['timeIn'] == null) {
        final status = determineInitialStatus(
          checkInTime: now,
          eventStart: halves.first.start,
          lateCutoffMinutes: lateCutoffMinutes,
        );
        data.addAll({
          'timeIn': verifiedAt,
          'status': status,
          'initialStatus': status,
        });
      }
    } else if (checkOutRequested &&
        part['timeOut'] == null &&
        !now.isBefore(checkOutOpensAt(halves[index]))) {
      part['timeOut'] = verifiedAt;
    } else {
      return null;
    }

    data['halves'] = parts;
    if (parts.every((h) => h['timeOut'] != null)) {
      data['timeOut'] = verifiedAt;
      data['status'] = inOutFinalStatus(data, halves.length);
    }
    return data;
  }

  // ---------------------------------------------------------------------------
  // Continuous Stay events: time away from the venue is summed from sessions.
  // ---------------------------------------------------------------------------

  /// Applies one location reading to a Continuous Stay record.
  /// Returns the updated record, or null when nothing needs saving.
  static Map<String, dynamic>? verifyContinuousAttendance({
    required Map<String, dynamic> existing,
    required Timestamp verifiedAt,
    required DateTime eventStart,
    required bool isInside,
    int lateCutoffMinutes = defaultLateCutoffMinutes,
  }) {
    if (existing['timeOut'] != null) return null;

    if (existing['timeIn'] == null) {
      if (!isInside) return null;
      final status = determineInitialStatus(
        checkInTime: verifiedAt.toDate(),
        eventStart: eventStart,
        lateCutoffMinutes: lateCutoffMinutes,
      );
      final record = AttendanceSessionRecord.createInitial(
        initialStatus: status,
        startedAt: verifiedAt,
      );
      return {...existing, ...record.sessionFields(), 'lastVerified': verifiedAt};
    }

    final lastSeen = existing['lastVerified'] as Timestamp?;
    final record = AttendanceSessionRecord.fromFirestore(
      existing,
    ).bootstrapLegacyIfNeeded(fallbackStart: lastSeen ?? verifiedAt);

    // If no inside reading was saved for a while (app closed, phone off),
    // the student left when the last reading went stale.
    final staleAt = lastSeen == null
        ? null
        : lastSeen.toDate().add(
            const Duration(seconds: heartbeatToleranceSeconds),
          );
    final wentStale =
        record.hasOpenSession &&
        staleAt != null &&
        staleAt.isBefore(verifiedAt.toDate());
    var next = wentStale
        ? record.leaveGeofence(Timestamp.fromDate(staleAt))
        : record;
    next = isInside ? next.enterGeofence(verifiedAt) : next.leaveGeofence(verifiedAt);

    final sessionsChanged =
        next.sessions.length != record.sessions.length ||
        next.hasOpenSession != record.hasOpenSession;
    final heartbeatDue =
        isInside &&
        (lastSeen == null ||
            verifiedAt.toDate().difference(lastSeen.toDate()).inSeconds >=
                heartbeatSeconds);
    if (!sessionsChanged && !heartbeatDue) return null;

    return {
      ...existing,
      ...next.sessionFields(),
      if (isInside) 'lastVerified': verifiedAt,
    };
  }

  // ---------------------------------------------------------------------------
  // End of event
  // ---------------------------------------------------------------------------

  /// Closes a record once its event has ended.
  /// Returns the fields to save, or null when the record is not due.
  static Map<String, dynamic>? finalizeIfEnded(
    Map<String, dynamic> data,
    Map<String, dynamic> event,
    DateTime now,
  ) {
    final end = (event['endTime'] as Timestamp?)?.toDate();
    if (end == null || data['timeOut'] != null || end.isAfter(now)) return null;
    final endTs = Timestamp.fromDate(end);

    final Map<String, dynamic> out;
    final type = (event['eventType'] ?? data['eventType'])?.toString();
    if (type == eventTypeInOut) {
      out = {
        ...data,
        'timeOut': endTs,
        'status': inOutFinalStatus(data, inOutHalves(event).length),
      };
    } else {
      final record = AttendanceSessionRecord.fromFirestore(
        data,
      ).finalize(endTs, lastSeen: data['lastVerified'] as Timestamp?);
      out = {...data, ...record.sessionFields()};
    }
    out['pointsAwarded'] = pointsFor(out['status'].toString(), basePointsOf(event));
    return out;
  }
}

class AttendanceSessionRecord {
  final int schemaVersion;
  final String eventType;
  final String initialStatus;
  final String status;
  final Timestamp? timeIn;
  final Timestamp? timeOut;
  final int totalOutsideSeconds;
  final List<Map<String, dynamic>> sessions;

  const AttendanceSessionRecord({
    required this.schemaVersion,
    required this.eventType,
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
    String eventType = AttendancePolicy.eventTypeContinuous,
  }) {
    return AttendanceSessionRecord(
      schemaVersion: AttendancePolicy.schemaVersion,
      eventType: eventType,
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
      eventType:
          data?['eventType']?.toString() ??
          AttendancePolicy.eventTypeContinuous,
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

  /// Closes the record at [at]. An open session is closed when the last
  /// inside reading ([lastSeen]) went stale, so silent absences count as away.
  AttendanceSessionRecord finalize(Timestamp at, {Timestamp? lastSeen}) {
    if (isFinalized) return this;

    final normalized = bootstrapLegacyIfNeeded(fallbackStart: at);
    final updatedSessions = normalized._cloneSessions();
    var updatedOutsideSeconds = normalized.totalOutsideSeconds;

    if (updatedSessions.isNotEmpty) {
      final lastSession = Map<String, dynamic>.from(updatedSessions.last);
      final lastTimeOut = lastSession['timeOut'] as Timestamp?;

      if (lastTimeOut == null) {
        var closeAt = at;
        if (lastSeen != null) {
          final staleAt = lastSeen.toDate().add(
            const Duration(seconds: AttendancePolicy.heartbeatToleranceSeconds),
          );
          final sessionStart = (lastSession['timeIn'] as Timestamp).toDate();
          if (staleAt.isBefore(at.toDate())) {
            closeAt = Timestamp.fromDate(
              staleAt.isBefore(sessionStart) ? sessionStart : staleAt,
            );
          }
        }
        lastSession['timeOut'] = closeAt;
        updatedSessions[updatedSessions.length - 1] = lastSession;
        updatedOutsideSeconds += _positiveDiffSeconds(closeAt, at);
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

  /// Record fields without the student/event identity.
  Map<String, dynamic> sessionFields() => {
    'schemaVersion': AttendancePolicy.schemaVersion,
    'eventType': eventType,
    'initialStatus': initialStatus,
    'status': status,
    'timeIn': timeIn,
    'timeOut': timeOut,
    'totalOutsideSeconds': totalOutsideSeconds,
    'sessions': sessions,
  };

  Map<String, dynamic> toFirestoreFields({
    required String studentId,
    required String eventId,
    required String eventTitle,
  }) {
    return {
      'schemaVersion': AttendancePolicy.schemaVersion,
      'eventType': eventType,
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
    String? eventType,
    String? initialStatus,
    String? status,
    Timestamp? timeIn,
    Object? timeOut = _sentinel,
    int? totalOutsideSeconds,
    List<Map<String, dynamic>>? sessions,
  }) {
    return AttendanceSessionRecord(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      eventType: eventType ?? this.eventType,
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
