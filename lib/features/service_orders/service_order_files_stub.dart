import 'dart:typed_data';

import 'service_order_files.dart';

ServiceOrderFiles createPlatformServiceOrderFiles() => _UnsupportedFiles();

class _UnsupportedFiles implements ServiceOrderFiles {
  static const _message =
      'A emissão de OS está disponível no aplicativo instalado.';

  @override
  Future<String> folderPath() async => throw UnsupportedError(_message);

  @override
  Future<String> write(String fileName, Uint8List bytes) async =>
      throw UnsupportedError(_message);

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<void> open(String path) async => throw UnsupportedError(_message);

  @override
  Future<void> openFolder() async => throw UnsupportedError(_message);
}
