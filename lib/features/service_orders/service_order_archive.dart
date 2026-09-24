import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/storage/local_snapshot_store.dart';
import 'service_order_details.dart';
import 'service_order_files.dart';
import 'service_order_issuer.dart';

/// Uma OS já emitida: o arquivo gravado e quando.
class IssuedServiceOrder {
  const IssuedServiceOrder({required this.path, required this.issuedAt});

  final String path;
  final DateTime issuedAt;

  String get fileName => path.split(RegExp(r'[\\/]')).last;

  Map<String, Object?> toJson() => {
    'path': path,
    'issuedAt': issuedAt.toIso8601String(),
  };

  static IssuedServiceOrder? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    final issuedAt = DateTime.tryParse(value['issuedAt'] as String? ?? '');
    if (path is! String || issuedAt == null) return null;
    return IssuedServiceOrder(path: path, issuedAt: issuedAt);
  }
}

/// Registro das OS emitidas, por atendimento.
///
/// O PDF fica numa pasta comum do usuário; o vínculo com o atendimento
/// fica no banco local. Assim a OS continua aparecendo no atendimento
/// mesmo que a pasta tenha outros arquivos, e a pasta continua útil por
/// si só, com nomes legíveis.
///
/// É deste computador, como a aparência: o PDF não sobe para o servidor.
/// Outro computador vê o atendimento, mas não as OS emitidas aqui.
class ServiceOrderArchive {
  ServiceOrderArchive({
    required LocalSnapshotStore store,
    ServiceOrderFiles? files,
    this.defaultIssuer = ServiceOrderIssuer.fromEnvironment,
  }) : _store = store,
       files = files ?? createServiceOrderFiles();

  /// Emitente usado enquanto nenhum foi salvo neste computador, e o que o
  /// botão "Usar meus dados padrão" traz de volta.
  final ServiceOrderIssuer defaultIssuer;

  static const _namespace = 'ordens-servico';
  static const _key = 'emitidas';

  final LocalSnapshotStore _store;
  final ServiceOrderFiles files;

  /// Todas as emissões, da mais recente para a mais antiga em cada
  /// atendimento. Uma leitura só, para a lista de atendimentos marcar
  /// quais já têm OS sem consultar o banco cartão a cartão.
  Future<Map<String, List<IssuedServiceOrder>>> loadAll() async {
    final raw = await _store.readMetadata(_namespace, _key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is List)
            entry.key as String: [
              for (final item in entry.value as List)
                ?IssuedServiceOrder.fromJson(item),
            ]..sort((a, b) => b.issuedAt.compareTo(a.issuedAt)),
      };
    } on FormatException catch (error) {
      // Perder o índice não apaga os PDFs, que continuam na pasta.
      debugPrint('ORION: índice de OS ilegível, recomeçando: $error');
      return {};
    }
  }

  Future<List<IssuedServiceOrder>> issuedFor(String caseId) async =>
      (await loadAll())[caseId] ?? const [];

  static const _issuerKey = 'emitente';
  static String _detailsKey(String caseId) => 'complementos:$caseId';

  /// Dados do emitente: os salvos neste computador ou, sem eles, o
  /// padrão do `.env`.
  Future<ServiceOrderIssuer> loadIssuer() async {
    final json = await _readJson(_issuerKey);
    return json == null ? defaultIssuer : ServiceOrderIssuer.fromJson(json);
  }

  Future<void> saveIssuer(ServiceOrderIssuer issuer) =>
      _store.writeMetadata(_namespace, _issuerKey, jsonEncode(issuer.toJson()));

  /// Complementos digitados na última vez que a janela da OS deste
  /// atendimento foi usada, ou nulo se nunca foi.
  Future<ServiceOrderDetails?> loadDetails(String caseId) async {
    final json = await _readJson(_detailsKey(caseId));
    return json == null ? null : ServiceOrderDetails.fromJson(json);
  }

  Future<void> saveDetails(String caseId, ServiceOrderDetails details) =>
      _store.writeMetadata(
        _namespace,
        _detailsKey(caseId),
        jsonEncode(details.toJson()),
      );

  Future<Map<dynamic, dynamic>?> _readJson(String key) async {
    final raw = await _store.readMetadata(_namespace, key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded : null;
    } on FormatException catch (error) {
      debugPrint('ORION: $key ilegível, ignorando: $error');
      return null;
    }
  }

  /// Grava o PDF e registra a emissão no atendimento.
  Future<IssuedServiceOrder> record({
    required String caseId,
    required String fileName,
    required Uint8List bytes,
    required DateTime issuedAt,
  }) async {
    final path = await files.write(fileName, bytes);
    final issued = IssuedServiceOrder(path: path, issuedAt: issuedAt);
    final all = await loadAll();
    all[caseId] = [issued, ...?all[caseId]];
    await _store.writeMetadata(
      _namespace,
      _key,
      jsonEncode({
        for (final entry in all.entries)
          entry.key: [for (final item in entry.value) item.toJson()],
      }),
    );
    return issued;
  }
}

/// Dá acesso ao [ServiceOrderArchive] a partir das telas.
class ServiceOrderScope extends InheritedWidget {
  const ServiceOrderScope({
    super.key,
    required this.archive,
    required super.child,
  });

  final ServiceOrderArchive archive;

  static ServiceOrderArchive? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServiceOrderScope>()?.archive;

  @override
  bool updateShouldNotify(ServiceOrderScope oldWidget) =>
      archive != oldWidget.archive;
}
