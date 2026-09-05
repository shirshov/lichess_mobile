import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Database {}

const _kDatabaseVersion = 5;
const _kDatabaseName = 'chess_openings$_kDatabaseVersion.db';

final openingsDatabaseProvider = FutureProvider<Database>((Ref ref) async {
  throw UnsupportedError('Not available on web');
}, name: 'OpeningsDatabaseProvider');

Future<Database> _openDb(String path) async {
  throw UnsupportedError('Not available on web');
}
