import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'service_order_files.dart';

ServiceOrderFiles createPlatformServiceOrderFiles() =>
    NativeServiceOrderFiles();

class NativeServiceOrderFiles implements ServiceOrderFiles {
  NativeServiceOrderFiles({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _baseDirectory;

  /// Na pasta Documentos do usuário, e não na pasta interna do
  /// aplicativo: a OS é um documento para anexar a e-mails, e tem de
  /// estar onde o usuário a encontra sozinho.
  @override
  Future<String> folderPath() async {
    final base = await _baseDirectory();
    return p.join(base.path, 'ORION ServiceLog', 'Ordens de serviço');
  }

  @override
  Future<String> write(String fileName, Uint8List bytes) async {
    final folder = Directory(await folderPath());
    await folder.create(recursive: true);
    final stem = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = File(p.join(folder.path, fileName));
    for (var copy = 2; await candidate.exists(); copy++) {
      candidate = File(p.join(folder.path, '$stem ($copy)$extension'));
    }
    // Grava ao lado e renomeia: um PDF pela metade, se o disco encher,
    // nunca fica com o nome definitivo.
    final partial = File('${candidate.path}.parcial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(candidate.path);
    return candidate.path;
  }

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<void> open(String path) => _launch(path);

  @override
  Future<void> openFolder() async {
    final folder = Directory(await folderPath());
    await folder.create(recursive: true);
    await _launch(folder.path);
  }

  /// Destacado do aplicativo: o visualizador de PDF continua aberto
  /// quando o ORION fecha, e o ORION não espera o visualizador fechar.
  static Future<void> _launch(String target) async {
    final (command, arguments) = switch (Platform.operatingSystem) {
      'linux' => ('xdg-open', [target]),
      'macos' => ('open', [target]),
      'windows' => ('explorer', [target]),
      _ => throw UnsupportedError('Não há como abrir arquivos neste sistema.'),
    };
    await Process.start(command, arguments, mode: ProcessStartMode.detached);
  }
}
