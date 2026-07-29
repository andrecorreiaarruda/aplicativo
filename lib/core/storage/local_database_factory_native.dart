import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database_configuration.dart';

Future<LocalDatabaseConfiguration> createLocalDatabaseConfiguration() async {
  sqfliteFfiInit();
  final directory = await getApplicationSupportDirectory();
  return LocalDatabaseConfiguration(
    factory: databaseFactoryFfi,
    path: path.join(directory.path, 'orion_servicelog.sqlite'),
    platformLabel: 'SQLite local',
  );
}
