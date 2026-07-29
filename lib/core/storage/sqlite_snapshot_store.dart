import 'package:sqflite_common/sqlite_api.dart';

import '../../data/sync/sync_operation.dart';
import 'local_database_factory.dart';
import 'local_snapshot_store.dart';

class SqliteSnapshotStore implements LocalSnapshotStore {
  SqliteSnapshotStore._({
    required Database database,
    required String storageLabel,
  }) : _database = database,
       _storageLabel = storageLabel;

  final Database _database;
  final String _storageLabel;

  static Future<SqliteSnapshotStore> open() async {
    final configuration = await createLocalDatabaseConfiguration();
    final database = await configuration.factory.openDatabase(
      configuration.path,
      options: OpenDatabaseOptions(
        version: 1,
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
              attempt_count INTEGER NOT NULL DEFAULT 0,
              last_attempt_at TEXT,
              last_error TEXT
            )
          ''');
          await database.execute('''
            CREATE INDEX idx_sync_queue_namespace_created
            ON sync_queue(namespace, created_at)
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
  Future<void> enqueue(SyncOperation operation) async {
    await _database.insert(
      'sync_queue',
      operation.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<SyncOperation>> pendingOperations(String namespace) async {
    final rows = await _database.query(
      'sync_queue',
      where: 'namespace = ?',
      whereArgs: [namespace],
      orderBy: 'created_at ASC',
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
  Future<void> markAttempt(String operationId, {required String? error}) async {
    await _database.rawUpdate(
      '''
      UPDATE sync_queue
      SET attempt_count = attempt_count + 1,
          last_attempt_at = ?,
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
