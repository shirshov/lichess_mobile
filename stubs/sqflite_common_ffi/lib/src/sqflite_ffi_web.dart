import 'dart:async';

import 'package:sqflite_common_ffi/src/sqflite_ffi_stub.dart'
    show SqfliteFfiStub;

DatabaseFactory get databaseFactoryFfi => SqfliteFfiStub();

typedef OnDatabaseVersionChange = FutureOr<void> Function(int? oldVersion, int? newVersion);

class DatabaseOptions {
  final OnDatabaseVersionChange? onDatabaseVersionChange;
  final bool singleInstance;

  const DatabaseOptions({
    this.onDatabaseVersionChange,
    this.singleInstance = true,
  });
}

class OpenDatabaseOptions {
  final int? version;
  final FutureOr<void> Function(Database db)? onConfigure;
  final FutureOr<void> Function(Database db)? onOpen;
  final FutureOr<void> Function(Database db, int oldVersion, int newVersion)? onCreate;
  final FutureOr<void> Function(Database db, int oldVersion, int newVersion)? onUpgrade;
  final FutureOr<void> Function(Database db, int oldVersion, int newVersion)? onDowngrade;
  final FutureOr<void> Function(Database db, int oldVersion, int newVersion)? onDatabaseVersionChange;

  const OpenDatabaseOptions({
    this.version,
    this.onConfigure,
    this.onOpen,
    this.onCreate,
    this.onUpgrade,
    this.onDowngrade,
    this.onDatabaseVersionChange,
  });
}

class SqfliteFfiStub {
  Future<Never> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async => throw UnsupportedError('sqflite_common_ffi is not supported on web');

  DatabaseFactory get factory => SqfliteFfiStub();
}

class SqfliteFfi {
  static Future<Never> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async => throw UnsupportedError('sqflite_common_ffi is not supported on web');

  static DatabaseFactory get factory => SqfliteFfiStub();
}
