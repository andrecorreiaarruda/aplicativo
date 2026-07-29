import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'local_database_configuration.dart';

Future<LocalDatabaseConfiguration> createLocalDatabaseConfiguration() async {
  return LocalDatabaseConfiguration(
    factory: databaseFactoryFfiWeb,
    path: 'orion_servicelog.sqlite',
    platformLabel: 'SQLite no navegador',
  );
}
