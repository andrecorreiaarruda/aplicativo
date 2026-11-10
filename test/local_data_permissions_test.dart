import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/local_database_factory_native.dart';

void main() {
  test(
    'a pasta de dados fica fechada para os outros usuários do sistema',
    () async {
      final directory = await Directory.systemTemp.createTemp('orion-dados-');
      addTearDown(() => directory.delete(recursive: true));
      await Process.run('chmod', ['755', directory.path]);

      await restrictToOwner(directory.path);

      // Os nove bits finais do modo: dono, grupo e outros.
      final permissions = directory.statSync().mode & 0x1FF;
      expect(permissions.toRadixString(8), '700');
    },
    skip: !(Platform.isLinux || Platform.isMacOS)
        ? 'Só se aplica a Linux e macOS.'
        : false,
  );

  test('pasta inexistente não derruba a abertura do aplicativo', () async {
    await expectLater(
      restrictToOwner('/caminho/que/nao/existe/orion'),
      completes,
    );
  });
}
