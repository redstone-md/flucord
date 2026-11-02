import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_log.dart';

/// Holds small cache writes for a moment, then applies them in one transaction.
///
/// A busy gateway asks for many small writes. Each commit on its own costs a
/// wait for the disk, so a burst here costs one commit instead. Writes apply in
/// the order they were added, so a delete added after a write has the last word.
///
/// Everything else that uses the database goes through [inTurn]. It runs after
/// all that was asked for before it, so a read always finds the writes before
/// it. If the app crashes, only the writes still waiting are lost: each flush
/// commits whole or not at all.
final class SqliteWriteQueue {
  SqliteWriteQueue(this._database, {required this.beforeCommit});

  /// How long a write may wait. It is short, because a crash loses what waits,
  /// and long enough to gather a burst.
  static const flushDelay = Duration(milliseconds: 200);

  final Database _database;

  /// Runs last in each flush, inside its transaction.
  final Future<void> Function(Transaction transaction) beforeCommit;

  final List<Future<void> Function(Transaction transaction)> _waiting = [];
  Timer? _timer;
  Future<void> _lastTurn = Future.value();
  bool _closed = false;

  /// Adds a write. It runs on the transaction it is given, and must not use the
  /// database directly, or the transaction would wait for itself. A write that
  /// arrives after [close] is dropped.
  void add(Future<void> Function(Transaction transaction) write) {
    if (_closed) return;
    _waiting.add(write);
    _timer ??= Timer(flushDelay, () => unawaited(flush()));
  }

  /// Finishes when every write added so far is committed.
  Future<void> flush() => inTurn(() async {});

  /// Runs [work] once all that was asked for before it has finished. A call to
  /// [inTurn] inside [work] would wait for itself.
  Future<T> inTurn<T>(Future<T> Function() work) {
    final result = _lastTurn.then((_) async {
      await _commitWaiting();
      return work();
    });
    _lastTurn = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Commits what still waits, then runs [closeDatabase]. Nothing is written
  /// after this.
  Future<void> close(Future<void> Function() closeDatabase) => inTurn(() async {
    // A write can arrive during the commit that this turn began with.
    await _commitWaiting();
    _closed = true;
    await closeDatabase();
  });

  /// A write that fails costs only itself, and a failed commit only this batch.
  /// Both cost the cached copy, and the screen has what it needs already.
  Future<void> _commitWaiting() async {
    _timer?.cancel();
    _timer = null;
    if (_waiting.isEmpty) return;
    final writes = [..._waiting];
    _waiting.clear();
    try {
      await _database.transaction((transaction) async {
        for (final write in writes) {
          try {
            await write(transaction);
          } catch (error) {
            _logFailure(error);
          }
        }
        await beforeCommit(transaction);
      });
    } catch (error) {
      _logFailure(error);
    }
  }

  void _logFailure(Object error) => AppLog.warning(
    'cache',
    'Could not write to the chat cache: $error',
    error: error,
  );
}
