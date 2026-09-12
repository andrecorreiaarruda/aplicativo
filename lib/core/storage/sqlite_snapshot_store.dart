import 'package:sqflite_common/sqlite_api.dart';

import '../../data/sync/sync_operation.dart';
import 'local_database_factory.dart';
import 'local_snapshot_store.dart';
import 'local_database_configuration.dart';
import 'outbox_mutation.dart';

class SqliteSnapshotStore implements LocalSnapshotStore {
  SqliteSnapshotStore._({
    required Database database,
    required String storageLabel,
  }) : _database = database,
       _storageLabel = storageLabel;

  final Database _database;
  final String _storageLabel;

  static Future<SqliteSnapshotStore> open({
    LocalDatabaseConfiguration? configuration,
  }) async {
    configuration ??= await createLocalDatabaseConfiguration();
    final database = await configuration.factory.openDatabase(
      configuration.path,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute(
              'ALTER TABLE sync_queue ADD COLUMN queue_order INTEGER NOT NULL DEFAULT 0',
            );
            await database.execute('''
              WITH ranked AS (
                SELECT id, ROW_NUMBER() OVER (
                  PARTITION BY namespace ORDER BY created_at, rowid
                ) AS position FROM sync_queue
              )
              UPDATE sync_queue SET queue_order = (
                SELECT position FROM ranked WHERE ranked.id = sync_queue.id
              )
            ''');
            await database.execute(
              'CREATE INDEX idx_sync_queue_order ON sync_queue(namespace, queue_order)',
            );
          }
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE app_snapshots (
              namespace TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE sync_queue (
              id TEXT PRIMARY KEY,
              namespace TEXT NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              operation TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at TEXT NOT NULL,
              queue_order INTEGER NOT NULL DEFAULT 0,
              attempt_count INTEGER NOT NULL DEFAULT 0,
              last_attempt_at TEXT,
              last_error TEXT
            )
          ''');
          await database.execute('''
            CREATE INDEX idx_sync_queue_order
            ON sync_queue(namespace, queue_order)
          ''');
          await database.execute('''
            CREATE TABLE app_metadata (
              namespace TEXT NOT NULL,
              metadata_key TEXT NOT NULL,
              metadata_value TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY(namespace, metadata_key)
            )
          ''');
        },
      ),
    );
    return SqliteSnapshotStore._(
      database: database,
      storageLabel: configuration.platformLabel,
    );
  }

  @override
  String get storageLabel => _storageLabel;

  @override
  Future<String?> readSnapshot(String namespace) async {
    final rows = await _database.query(
      'app_snapshots',
      columns: ['payload'],
      where: 'namespace = ?',
      whereArgs: [namespace],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['payload'] as String?;
  }

  @override
  Future<void> writeSnapshot(String namespace, String value) async {
    await _database.insert('app_snapshots', {
      'namespace': namespace,
      'payload': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeSnapshot(String namespace) async {
    await _database.delete(
      'app_snapshots',
      where: 'namespace = ?',
      whereArgs: [namespace],
    );
  }

  @override
  Future<void> commitMutation({
    required String namespace,
    String? snapshot,
    List<SyncOperation> operations = const [],
    SyncOperation? completed,
    int? revision,
  }) async {
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'sync_queue',
        where: 'namespace = ?',
        whereArgs: [namespace],
        orderBy: 'queue_order ASC, rowid ASC',
      );
      final current = rows.map(SyncOperation.fromRow).toList();
      final next = mutateOutbox(
        current,
        namespace,
        operations,
        completed,
        revision,
      );
      if (snapshot != null) {
        await txn.insert('app_snapshots', {
          'namespace': namespace,
          'payload': snapshot,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final old in current) {
        if (!next.any((item) => item.id == old.id)) {
          await txn.delete('sync_queue', where: 'id = ?', whereArgs: [old.id]);
        }
      }
      for (final item in next) {
        final exists = current.any((old) => old.id == item.id);
        if (!exists) {
          await txn.insert('sync_queue', item.toRow());
        } else if (completed != null &&
            item.attemptCount == 0 &&
            item.entityId == completed.entityId &&
            item.entityType == completed.entityType) {
          await txn.update(
            'sync_queue',
            {'payload': item.payloadJson},
            where: 'id = ?',
            whereArgs: [item.id],
          );
        }
      }
    });
  }

  @override
  Future<SyncOperation?> claimOperation(String operationId) =>
      _database.transaction((txn) async {
        final rows = await txn.query(
          'sync_queue',
          where: 'id = ?',
          whereArgs: [operationId],
        );
        if (rows.isEmpty) return null;
        final item = SyncOperation.fromRow(rows.single);
        final claimed = item.copyWith(
          attemptCount: item.attemptCount + 1,
          lastAttemptAt: DateTime.now(),
        );
        await txn.update(
          'sync_queue',
          claimed.toRow(),
          where: 'id = ?',
          whereArgs: [operationId],
        );
        return claimed;
      });

  @override
  Future<void> enqueue(SyncOperation operation) =>
      commitMutation(namespace: operation.namespace, operations: [operation]);

  @override
  Future<List<SyncOperation>> pendingOperations(String namespace) async {
    final rows = await _database.query(
      'sync_queue',
      where: 'namespace = ?',
      whereArgs: [namespace],
      orderBy: 'queue_order ASC, rowid ASC',
    );
    return rows.map(SyncOperation.fromRow).toList(growable: false);
  }

  @override
  Future<int> pendingCount(String namespace) async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_queue WHERE namespace = ?',
      [namespace],
    );
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> recordFailure(
    String operationId, {
    required String? error,
  }) async {
    await _database.rawUpdate(
      '''
      UPDATE sync_queue
      SET last_attempt_at = ?,
          last_error = ?
      WHERE id = ?
      ''',
      [DateTime.now().toUtc().toIso8601String(), error, operationId],
    );
  }

  @override
  Future<void> removeOperation(String operationId) async {
    await _database.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [operationId],
    );
  }

  @override
  Future<String?> readMetadata(String namespace, String key) async {
    final rows = await _database.query(
      'app_metadata',
      columns: ['metadata_value'],
      where: 'namespace = ? AND metadata_key = ?',
      whereArgs: [namespace, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['metadata_value'] as String?;
  }

  @override
  Future<void> writeMetadata(String namespace, String key, String value) async {
    await _database.insert('app_metadata', {
      'namespace': namespace,
      'metadata_key': key,
      'metadata_value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() => _database.close();
}
