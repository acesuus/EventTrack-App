import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseHelper {
  static final LocalDatabaseHelper _instance = LocalDatabaseHelper._internal();
  static Database? _database;

  factory LocalDatabaseHelper() {
    return _instance;
  }

  LocalDatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    String databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'event_track.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        venueName TEXT,
        lat REAL,
        lng REAL,
        startTime INTEGER,
        endTime INTEGER,
        lateCutoffMinutes INTEGER
      )
    ''');
  }
}
