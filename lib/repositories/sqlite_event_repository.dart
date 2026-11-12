import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/local_database_helper.dart';
import 'event_repository.dart';

class SqliteEventRepository implements IEventRepository {
  final LocalDatabaseHelper _dbHelper = LocalDatabaseHelper();
  final _uuid = const Uuid();

  @override
  Stream<List<Map<String, dynamic>>> getActiveEventsStream() async* {
    final db = await _dbHelper.database;

    // Query local database
    final List<Map<String, dynamic>> maps = await db.query(
      'events',
      orderBy: 'startTime DESC',
    );

    // Yield mapped data
    yield maps.map((map) {
      final data = Map<String, dynamic>.from(map);

      // Translate SQLite INTEGER (milliseconds since epoch) back to Firestore Timestamp
      if (data['startTime'] != null) {
        data['startTime'] = Timestamp.fromMillisecondsSinceEpoch(
          data['startTime'] as int,
        );
      }
      if (data['endTime'] != null) {
        data['endTime'] = Timestamp.fromMillisecondsSinceEpoch(
          data['endTime'] as int,
        );
      }

      return data;
    }).toList();
  }

  @override
  Future<void> createEvent(Map<String, dynamic> eventData) async {
    final db = await _dbHelper.database;

    final id = eventData['id'] ?? _uuid.v4();
    final row = _mapToSqliteRow(id, eventData);

    await db.insert(
      'events',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateEvent(
    String eventId,
    Map<String, dynamic> eventData,
  ) async {
    final db = await _dbHelper.database;

    final row = _mapToSqliteRow(eventId, eventData);

    await db.update('events', row, where: 'id = ?', whereArgs: [eventId]);
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    final db = await _dbHelper.database;

    await db.delete('events', where: 'id = ?', whereArgs: [eventId]);
  }

  Map<String, Object?> _mapToSqliteRow(
    String id,
    Map<String, dynamic> eventData,
  ) {
    int? startTimeMillis;
    int? endTimeMillis;

    if (eventData['startTime'] is Timestamp) {
      startTimeMillis =
          (eventData['startTime'] as Timestamp).millisecondsSinceEpoch;
    }
    if (eventData['endTime'] is Timestamp) {
      endTimeMillis =
          (eventData['endTime'] as Timestamp).millisecondsSinceEpoch;
    }

    return {
      'id': id,
      'title': eventData['title'],
      'description': eventData['description'],
      'venueName': eventData['venueName'],
      'lat': eventData['lat'],
      'lng': eventData['lng'],
      'startTime': startTimeMillis,
      'endTime': endTimeMillis,
      'lateCutoffMinutes': eventData['lateCutoffMinutes'],
    };
  }

  @override
  Future<void> executeManualFallbackCheckIn(
    String eventId,
    String studentId,
  ) async {
    throw UnimplementedError(
      'Manual fallback check-in is not supported in offline mode.',
    );
  }
}
