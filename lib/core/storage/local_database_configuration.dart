import 'package:sqflite_common/sqlite_api.dart';

class LocalDatabaseConfiguration {
  const LocalDatabaseConfiguration({
    required this.factory,
    required this.path,
    required this.platformLabel,
  });

  final DatabaseFactory factory;
  final String path;
  final String platformLabel;
}
