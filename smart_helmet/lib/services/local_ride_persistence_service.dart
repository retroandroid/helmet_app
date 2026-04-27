import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/ride_stats.dart';

class LocalRidePersistenceService {
  static const _databaseName = 'rideguard_local.db';
  static const _databaseVersion = 1;
  static const _tableName = 'rides';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasesPath = await getDatabasesPath();
    final databasePath = path.join(databasesPath, _databaseName);

    _database = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            remote_id INTEGER UNIQUE,
            user_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            start_lat REAL,
            start_lng REAL,
            end_lat REAL,
            end_lng REAL,
            max_speed_kmh REAL,
            avg_speed_kmh REAL,
            max_bpm INTEGER,
            avg_bpm INTEGER,
            min_spo2 INTEGER,
            max_co INTEGER,
            max_alcohol REAL,
            avg_temperature REAL,
            avg_humidity REAL,
            max_force REAL,
            min_distance REAL,
            had_crash INTEGER NOT NULL DEFAULT 0,
            had_obstacle_alert INTEGER NOT NULL DEFAULT 0,
            had_co_alert INTEGER NOT NULL DEFAULT 0,
            had_dont_drive_alert INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );

    return _database!;
  }

  Future<int> createRide({
    required String userId,
    required DateTime startedAt,
    double? startLat,
    double? startLng,
  }) async {
    final db = await database;
    return db.insert(_tableName, {
      'user_id': userId,
      'started_at': startedAt.toUtc().toIso8601String(),
      'start_lat': startLat,
      'start_lng': startLng,
    });
  }

  Future<void> setRemoteId({
    required int localRideId,
    required int remoteRideId,
  }) async {
    final db = await database;
    await db.update(
      _tableName,
      {'remote_id': remoteRideId},
      where: 'id = ?',
      whereArgs: [localRideId],
    );
  }

  Future<void> endRide({
    required int localRideId,
    required DateTime endedAt,
    double? endLat,
    double? endLng,
    required RideStats stats,
  }) async {
    final db = await database;
    await db.update(
      _tableName,
      {
        'ended_at': endedAt.toUtc().toIso8601String(),
        'end_lat': endLat,
        'end_lng': endLng,
        'max_speed_kmh': stats.maxSpeedKmh,
        'avg_speed_kmh': stats.avgSpeedKmh,
        'max_bpm': stats.maxBpm,
        'avg_bpm': stats.avgBpm,
        'min_spo2': stats.minSpo2,
        'max_co': stats.maxCo,
        'max_alcohol': stats.maxAlcohol,
        'avg_temperature': stats.avgTemperature,
        'avg_humidity': stats.avgHumidity,
        'max_force': stats.maxForce,
        'min_distance': stats.minDistance,
        'had_crash': stats.hadCrash ? 1 : 0,
        'had_obstacle_alert': stats.hadObstacleAlert ? 1 : 0,
        'had_co_alert': stats.hadCoAlert ? 1 : 0,
        'had_dont_drive_alert': stats.hadDontDriveAlert ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [localRideId],
    );
  }

  Future<Map<String, dynamic>?> fetchRideByLocalId(int localRideId) async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [localRideId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _normalizeRide(rows.first);
  }

  Future<List<Map<String, dynamic>>> fetchRidesForUser(String userId) async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
    );

    return rows.map(_normalizeRide).toList();
  }

  Future<void> upsertRemoteRide(Map<String, dynamic> ride) async {
    final db = await database;
    final normalized = {
      'remote_id': ride['id'],
      'user_id': ride['user_id'],
      'started_at': ride['started_at'],
      'ended_at': ride['ended_at'],
      'start_lat': ride['start_lat'],
      'start_lng': ride['start_lng'],
      'end_lat': ride['end_lat'],
      'end_lng': ride['end_lng'],
      'max_speed_kmh': ride['max_speed_kmh'],
      'avg_speed_kmh': ride['avg_speed_kmh'],
      'max_bpm': ride['max_bpm'],
      'avg_bpm': ride['avg_bpm'],
      'min_spo2': ride['min_spo2'],
      'max_co': ride['max_co'],
      'max_alcohol': ride['max_alcohol'],
      'avg_temperature': ride['avg_temperature'],
      'avg_humidity': ride['avg_humidity'],
      'max_force': ride['max_force'],
      'min_distance': ride['min_distance'],
      'had_crash': _asDatabaseBool(ride['had_crash']),
      'had_obstacle_alert': _asDatabaseBool(ride['had_obstacle_alert']),
      'had_co_alert': _asDatabaseBool(ride['had_co_alert']),
      'had_dont_drive_alert': _asDatabaseBool(ride['had_dont_drive_alert']),
    };

    final existingRows = await db.query(
      _tableName,
      columns: ['id'],
      where: 'remote_id = ?',
      whereArgs: [ride['id']],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      await db.insert(_tableName, normalized);
      return;
    }

    await db.update(
      _tableName,
      normalized,
      where: 'id = ?',
      whereArgs: [existingRows.first['id']],
    );
  }

  Map<String, dynamic> _normalizeRide(Map<String, dynamic> row) {
    return {
      ...row,
      'had_crash': _asBool(row['had_crash']),
      'had_obstacle_alert': _asBool(row['had_obstacle_alert']),
      'had_co_alert': _asBool(row['had_co_alert']),
      'had_dont_drive_alert': _asBool(row['had_dont_drive_alert']),
    };
  }

  int _asDatabaseBool(dynamic value) {
    return _asBool(value) ? 1 : 0;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }
}
