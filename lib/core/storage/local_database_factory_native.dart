import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database_configuration.dart';

Future<LocalDatabaseConfiguration> createLocalDatabaseConfiguration() async {
  sqfliteFfiInit();
  final directory = await getApplicationSupportDirectory();
  await restrictToOwner(directory.path);
  return LocalDatabaseConfiguration(
    factory: databaseFactoryFfi,
    path: path.join(directory.path, 'orion_servicelog.sqlite'),
    platformLabel: 'SQLite local',
  );
}

/// Fecha a pasta de dados do aplicativo para os outros usuários do
/// computador.
///
/// No Linux e no macOS a pasta nasce legível por todos (modo 755). Dentro
/// dela ficam o banco, com os dados dos clientes, e o arquivo em que o
/// Supabase guarda a sessão — quem lê esse arquivo entra na conta sem
/// senha. Em computador de uso compartilhado, outro usuário do sistema
/// conseguiria abrir os dois.
///
/// No Windows a pasta já fica dentro do perfil do usuário, que o sistema
/// isola; em Android e iOS, dentro da área privada do aplicativo.
///
/// Falhar aqui não impede o aplicativo de abrir: é proteção adicional.
@visibleForTesting
Future<void> restrictToOwner(String directory) async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  try {
    final result = await Process.run('chmod', ['700', directory]);
    if (result.exitCode != 0) {
      debugPrint('ORION: chmod 700 em $directory falhou: ${result.stderr}');
    }
  } on ProcessException catch (error) {
    debugPrint('ORION: não foi possível restringir $directory: $error');
  }
}
