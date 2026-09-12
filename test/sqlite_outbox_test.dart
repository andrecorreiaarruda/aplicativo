import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:servicelog_ai/core/storage/local_database_configuration.dart';
import 'package:servicelog_ai/core/storage/sqlite_snapshot_store.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/data/sync/sync_operation.dart';

void main() {
  late Directory directory;
  late LocalDatabaseConfiguration config;
  late SqliteSnapshotStore store;
  late Database db;
  late DemoServiceLogRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('orion-outbox-');
    config = LocalDatabaseConfiguration(
      factory: databaseFactoryFfiNoIsolate,
      path: '${directory.path}/test.sqlite',
      platformLabel: 'SQLite test',
    );
    store = await SqliteSnapshotStore.open(configuration: config);
    db = await config.factory.openDatabase(config.path);
    repository = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'a',
    );
    await repository.fetchEquipmentCatalog();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('falha entre snapshot e outbox reverte disco e memória', () async {
    final before = await store.readSnapshot('a');
    await db.execute(
      "CREATE TRIGGER fail_insert BEFORE INSERT ON sync_queue BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
    );
    await expectLater(
      repository.createCustomer(const CustomerDraft(name: 'Não salvo')),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.readSnapshot('a'), before);
    expect(await store.pendingCount('a'), 0);
    expect((await repository.fetchEquipmentCatalog()).customers, isEmpty);
    await db.execute('DROP TRIGGER fail_insert');
    await repository.createCustomer(const CustomerDraft(name: 'Salvo'));
    await store.close();
    store = await SqliteSnapshotStore.open(configuration: config);
    final reopened = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'a',
    );
    expect(
      (await reopened.fetchEquipmentCatalog()).customers.single.name,
      'Salvo',
    );
    expect(await store.pendingCount('a'), 1);
  });

  test('falha na compactação preserva operação e snapshot anteriores', () async {
    final id = await repository.createCustomer(
      const CustomerDraft(name: 'Original'),
    );
    final before = await store.readSnapshot('a');
    final old = (await store.pendingOperations('a')).single;
    await db.execute(
      "CREATE TRIGGER fail_insert BEFORE INSERT ON sync_queue BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
    );
    await expectLater(
      repository.updateCustomer(id, const CustomerDraft(name: 'Editado')),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.readSnapshot('a'), before);
    expect((await store.pendingOperations('a')).single.id, old.id);
    expect(
      (await repository.fetchEquipmentCatalog()).customers.single.name,
      'Original',
    );
  });

  test('cliente e local são uma única transação', () async {
    await db.execute(
      "CREATE TRIGGER fail_site BEFORE INSERT ON sync_queue WHEN NEW.entity_type = 'site' BEGIN SELECT RAISE(ABORT, 'site failure'); END",
    );
    await expectLater(
      repository.createCustomerSite(
        const CustomerSiteDraft(customerName: 'Hospital', siteName: 'Sala'),
      ),
      throwsA(isA<DatabaseException>()),
    );
    final catalog = await repository.fetchEquipmentCatalog();
    expect(catalog.customers, isEmpty);
    expect(catalog.sites, isEmpty);
    expect(await store.pendingCount('a'), 0);
  });

  test('envio incerto sobrevive reinício sem trocar ID ou payload', () async {
    final id = await repository.createCustomer(
      const CustomerDraft(name: 'Primeiro'),
    );
    final original = (await store.pendingOperations('a')).single;
    await store.claimOperation(original.id);
    await store.close();
    store = await SqliteSnapshotStore.open(configuration: config);
    repository = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'a',
    );
    await repository.updateCustomer(id, const CustomerDraft(name: 'Segundo'));
    await repository.updateCustomer(id, const CustomerDraft(name: 'Terceiro'));
    final queued = await store.pendingOperations('a');
    expect(queued, hasLength(2));
    expect(queued.first.id, original.id);
    expect(queued.first.payloadJson, original.payloadJson);
    expect(queued.first.attemptCount, 1);
    expect(queued.last.payload['name'], 'Terceiro');
    await repository.acknowledge(queued.first, 7);
    final successor = (await store.pendingOperations('a')).single;
    expect(successor.expectedRevision, 7);
    expect(successor.payload['name'], 'Terceiro');
    expect(repository.remoteRevision('customer', id), 7);
  });

  test(
    'falha ao confirmar mantém recibo pendente, revisão e sucessora',
    () async {
      final id = await repository.createCustomer(
        const CustomerDraft(name: 'Primeiro'),
      );
      final original = (await store.pendingOperations('a')).single;
      await store.claimOperation(original.id);
      await repository.updateCustomer(id, const CustomerDraft(name: 'Segundo'));
      final before = await store.readSnapshot('a');
      await db.execute(
        "CREATE TRIGGER fail_delete BEFORE DELETE ON sync_queue BEGIN SELECT RAISE(ABORT, 'ack failure'); END",
      );
      await expectLater(
        repository.acknowledge(original, 8),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.readSnapshot('a'), before);
      expect(repository.remoteRevision('customer', id), 0);
      expect(await store.pendingCount('a'), 2);
      expect((await store.pendingOperations('a')).last.expectedRevision, 0);
      await db.execute('DROP TRIGGER fail_delete');
      await repository.acknowledge(original, 8);
      expect((await store.pendingOperations('a')).single.expectedRevision, 8);
    },
  );

  test(
    'namespace diferente não é modificado por compactação ou confirmação',
    () async {
      await store.commitMutation(
        namespace: 'b',
        snapshot: 'other',
        operations: [
          SyncOperation(
            id: 'other',
            namespace: 'b',
            entityType: 'customer',
            entityId: 'id',
            operation: 'upsert',
            payload: const {},
            createdAt: DateTime.now(),
          ),
        ],
      );
      final id = await repository.createCustomer(
        const CustomerDraft(name: 'Um'),
      );
      await repository.updateCustomer(id, const CustomerDraft(name: 'Dois'));
      expect(await store.readSnapshot('b'), 'other');
      expect((await store.pendingOperations('b')).single.id, 'other');
    },
  );

  test('migração v1 para v2 preserva snapshot, UUID e tentativa pendente', () async {
    final id = await repository.createCustomer(
      const CustomerDraft(name: 'Legado'),
    );
    final snapshot = await store.readSnapshot('a');
    final old = (await store.pendingOperations('a')).single;
    await store.close();
    config = LocalDatabaseConfiguration(
      factory: databaseFactoryFfiNoIsolate,
      path: '${directory.path}/legacy.sqlite',
      platformLabel: 'SQLite legacy',
    );
    db = await config.factory.openDatabase(
      config.path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE app_snapshots(namespace TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE sync_queue(id TEXT PRIMARY KEY, namespace TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, attempt_count INTEGER NOT NULL DEFAULT 0, last_attempt_at TEXT, last_error TEXT)',
          );
          await db.execute(
            'CREATE TABLE app_metadata(namespace TEXT NOT NULL, metadata_key TEXT NOT NULL, metadata_value TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(namespace,metadata_key))',
          );
        },
      ),
    );
    await db.insert('app_snapshots', {
      'namespace': 'a',
      'payload': snapshot,
      'updated_at': '2026-09-07',
    });
    final legacyRow = old.toRow()..remove('queue_order');
    legacyRow['attempt_count'] = 1;
    // Physical insertion order can differ after old compactions.
    final laterRow = Map<String, Object?>.from(legacyRow)
      ..['id'] = 'legacy-later'
      ..['entity_id'] = 'another-customer'
      ..['created_at'] = old.createdAt
          .add(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String();
    await db.insert('sync_queue', laterRow);
    await db.insert('sync_queue', legacyRow);
    await db.close();
    store = await SqliteSnapshotStore.open(configuration: config);
    db = await config.factory.openDatabase(config.path);
    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 2);
    expect(await store.readSnapshot('a'), snapshot);
    repository = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'a',
    );
    await repository.updateCustomer(
      id,
      const CustomerDraft(name: 'Atualizado'),
    );
    final queued = await store.pendingOperations('a');
    expect(queued, hasLength(3));
    expect(queued[1].id, 'legacy-later');
    expect(queued.first.id, old.id);
    expect(queued.first.payloadJson, old.payloadJson);
    expect(queued.first.attemptCount, 1);
    expect(queued.last.payload['name'], 'Atualizado');
  });

  test('compactação mantém ordem causal mesmo com timestamps iguais', () async {
    final now = DateTime.utc(2026);
    SyncOperation op(String id, String type, String entity) => SyncOperation(
      id: id,
      namespace: 'a',
      entityType: type,
      entityId: entity,
      operation: 'upsert',
      payload: const {},
      createdAt: now,
    );
    await store.commitMutation(
      namespace: 'a',
      operations: [op('parent', 'customer', 'c'), op('child', 'site', 's')],
    );
    await store.commitMutation(
      namespace: 'a',
      operations: [op('edited-parent', 'customer', 'c')],
    );
    expect((await store.pendingOperations('a')).map((e) => e.id), [
      'edited-parent',
      'child',
    ]);
  });

  test('gravações concorrentes preservam todos os registros', () async {
    await Future.wait(
      List.generate(
        12,
        (i) => repository.createCustomer(CustomerDraft(name: 'Cliente $i')),
      ),
    );
    expect((await repository.fetchEquipmentCatalog()).customers, hasLength(12));
    expect(await store.pendingCount('a'), 12);
    final reopened = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'a',
    );
    expect((await reopened.fetchEquipmentCatalog()).customers, hasLength(12));
  });

  test('snapshot corrompido é preservado para recuperação', () async {
    await store.writeSnapshot('bad', '{invalid');
    final bad = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'bad',
    );
    await expectLater(bad.fetchEquipmentCatalog(), throwsFormatException);
    expect(await store.readSnapshot('bad'), '{invalid');
  });
}
