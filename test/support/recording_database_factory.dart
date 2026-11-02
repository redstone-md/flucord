import 'dart:typed_data';

import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A real database factory that also tells what happened on its databases.
///
/// Nothing is faked, so a test reads what SQLite really did: how many commits
/// it took, and what the open connection reports about its settings.
final class RecordingDatabaseFactory implements DatabaseFactory {
  RecordingDatabaseFactory(DatabaseFactory factory) {
    // The only way the package offers to watch its statements. It is used in
    // tests alone, so a change in it can break no release.
    // ignore: experimental_member_use
    _factory = SqfliteDatabaseFactoryLogger(
      factory,
      options: SqfliteLoggerOptions(log: _record),
    );
  }

  late final DatabaseFactory _factory;

  /// The database opened last.
  Database? opened;

  /// How many commits were made. A transaction is one, and so is each write
  /// that ran outside a transaction.
  int commits = 0;

  void _record(SqfliteLoggerEvent event) {
    if (event is! SqfliteLoggerSqlEvent) return;
    final sql = event.sql.trimLeft().toUpperCase();
    final isLoneWrite =
        event.transactionId == null &&
        (sql.startsWith('INSERT') ||
            sql.startsWith('UPDATE') ||
            sql.startsWith('DELETE'));
    if (sql == 'COMMIT' || isLoneWrite) commits++;
  }

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async => opened = await _factory.openDatabase(path, options: options);

  @override
  Future<String> getDatabasesPath() => _factory.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) => _factory.setDatabasesPath(path);

  @override
  Future<void> deleteDatabase(String path) => _factory.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) => _factory.databaseExists(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      _factory.writeDatabaseBytes(path, bytes);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      _factory.readDatabaseBytes(path);
}
