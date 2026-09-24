import 'dart:typed_data';

import 'service_order_files_stub.dart'
    if (dart.library.io) 'service_order_files_native.dart';

/// Onde as OS emitidas ficam gravadas, e como abri-las.
///
/// Separado do resto para que a versão web do aplicativo continue
/// compilando — lá não há sistema de arquivos — e para que os testes
/// troquem o disco por memória.
abstract class ServiceOrderFiles {
  /// Pasta das OS, para mostrar ao usuário onde procurar.
  Future<String> folderPath();

  /// Grava o PDF e devolve o caminho completo. Nunca sobrescreve: se já
  /// houver um arquivo com o mesmo nome, acrescenta um sufixo.
  Future<String> write(String fileName, Uint8List bytes);

  Future<bool> exists(String path);

  /// Abre o PDF no visualizador padrão do sistema.
  Future<void> open(String path);

  /// Abre a pasta das OS no gerenciador de arquivos, para arrastar o PDF
  /// para um e-mail.
  Future<void> openFolder();
}

ServiceOrderFiles createServiceOrderFiles() =>
    createPlatformServiceOrderFiles();
