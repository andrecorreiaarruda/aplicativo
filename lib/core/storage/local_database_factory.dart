import 'local_database_configuration.dart';
import 'local_database_factory_native.dart'
    if (dart.library.html) 'local_database_factory_web.dart'
    as platform;

Future<LocalDatabaseConfiguration> createLocalDatabaseConfiguration() =>
    platform.createLocalDatabaseConfiguration();
