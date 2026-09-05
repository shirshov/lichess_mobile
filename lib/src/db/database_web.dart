import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

const kLichessDatabaseName = 'lichess_mobile.db';

const puzzleTTL = Duration(days: 60);
const corresGameTTL = Duration(days: 60);
const gameTTL = Duration(days: 90);
const chatReadMessagesTTL = Duration(days: 180);
const httpLogTTL = Duration(days: 7);
const appLogTTL = Duration(days: 7);

const kStorageAnonId = '**anonymous**';

final _logger = Logger('Database');

/// A provider for the app [Database].
///
/// On web, sqflite is not supported, so this provider throws
/// [UnsupportedError].
final databaseProvider = FutureProvider<Database>((Ref ref) async {
  throw UnsupportedError('Database not supported on web');
}, name: 'DatabaseProvider');

/// Returns the database path including filename.
///
/// On web, this throws [UnsupportedError] because the filesystem
/// path is not available.
Future<String> get _databasePath async {
  throw UnsupportedError('Database not supported on web');
}

Future<int?> _getDatabaseVersion(Database db) async {
  return null;
}

/// A provider that returns the size of the database file in bytes.
///
/// On web, this throws [UnsupportedError] because the filesystem
/// is not available.
final getDbSizeInBytesProvider = FutureProvider<int>((Ref ref) async {
  throw UnsupportedError('Database not supported on web');
}, name: 'GetDbSizeInBytesProvider');

/// Opens the app database.
///
/// On web, this throws [UnsupportedError] because sqflite is not
/// supported.
Future<Database> openAppDatabase(DatabaseFactory dbFactory, String path) {
  throw UnsupportedError('Database not supported on web');
}

void _createPuzzleBatchTableV3(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS puzzle_batchs');
  batch.execute('''
    CREATE TABLE puzzle_batchs(
      userId TEXT NOT NULL,
      angle TEXT NOT NULL,
      lastModified TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      data TEXT NOT NULL,
      PRIMARY KEY (userId, angle)
    )
    ''');
}

void _updatePuzzleBatchTableToV3(Batch batch) {
  batch.execute('''
    CREATE TABLE puzzle_batchs_new(
      userId TEXT NOT NULL,
      angle TEXT NOT NULL,
      lastModified TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      data TEXT NOT NULL,
      PRIMARY KEY (userId, angle)
    )
    ''');
  batch.execute('''
    INSERT INTO puzzle_batchs_new(userId, angle, data)
    SELECT userId, angle, data FROM puzzle_batchs
    ''');
  batch.execute('DROP TABLE puzzle_batchs');
  batch.execute('ALTER TABLE puzzle_batchs_new RENAME TO puzzle_batchs');
}

void _createPuzzleTableV1(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS puzzle');
  batch.execute('''
    CREATE TABLE puzzle(
    puzzleId TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (puzzleId)
  )
    ''');
}

void _createCorrespondenceGameTableV1(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS correspondence_game');
  batch.execute('''
    CREATE TABLE correspondence_game(
    gameId TEXT NOT NULL,
    userId TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (gameId)
  )
    ''');
}

void _createGameTableV2(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS game');
  batch.execute('''
    CREATE TABLE game(
    gameId TEXT NOT NULL,
    userId TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (gameId)
  )
    ''');
}

void _createChatReadMessagesTableV1(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS chat_read_messages');
  batch.execute('''
    CREATE TABLE chat_read_messages(
    id TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    nbRead INTEGER NOT NULL,
    PRIMARY KEY (id)
  )
    ''');
}

void _createHttpLogTableV4(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS http_log');
  batch.execute('''
    CREATE TABLE http_log(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    httpLogId TEXT NOT NULL UNIQUE,
    requestDateTime TEXT NOT NULL,
    requestMethod TEXT NOT NULL,
    requestUrl TEXT NOT NULL,
    responseCode INTEGER,
    responseDateTime TEXT,
    lastModified TEXT NOT NULL,
    errorMessage TEXT
  )
    ''');
}

void _createAppLogTableV5(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS app_log');
  batch.execute('''
    CREATE TABLE app_log(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    logTime TEXT NOT NULL,
    loggerName TEXT NOT NULL,
    levelValue INTEGER NOT NULL,
    levelName TEXT NOT NULL,
    message TEXT NOT NULL,
    error TEXT,
    stackTrace TEXT,
    lastModified TEXT NOT NULL
  )
    ''');
}

Future<void> _deleteOldEntries(DatabaseExecutor db, String table, Duration ttl) async {
  final date = DateTime.now().subtract(ttl);

  if (!await _doesTableExist(db, table)) {
    return;
  }

  await db.delete(table, where: 'lastModified < ?', whereArgs: [date.toIso8601String()]);
}

Future<bool> _doesTableExist(DatabaseExecutor db, String table) async {
  final tableExists = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
  );

  return tableExists.isNotEmpty;
}
