import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/models/service_time_metrics.dart';

ServiceProgressEntry _session({
  required String id,
  required DateTime start,
  DateTime? end,
}) {
  return ServiceProgressEntry(
    id: id,
    occurredAt: start,
    endedAt: end,
    description: 'Sessão $id',
  );
}

void main() {
  final base = DateTime.utc(2026, 8, 1, 8);

  group('serviceMinutes', () {
    test('soma a duração das sessões encerradas', () {
      final entries = [
        _session(id: '1', start: base, end: base.add(const Duration(hours: 2))),
        _session(
          id: '2',
          start: base.add(const Duration(days: 1)),
          end: base.add(const Duration(days: 1, minutes: 90)),
        ),
      ];

      expect(ServiceTimeMetrics.serviceMinutes(entries), 210);
    });

    test('ignora sessões em aberto', () {
      final entries = [
        _session(id: '1', start: base, end: base.add(const Duration(hours: 1))),
        _session(id: '2', start: base.add(const Duration(hours: 3))),
      ];

      expect(ServiceTimeMetrics.serviceMinutes(entries), 60);
    });

    test('retorna zero quando não há sessão registrada', () {
      expect(ServiceTimeMetrics.serviceMinutes(const []), 0);
    });
  });

  group('downtimeToServiceRatio', () {
    test('divide indisponibilidade por tempo técnico', () {
      expect(
        ServiceTimeMetrics.downtimeToServiceRatio(
          downtimeMinutes: 600,
          serviceMinutes: 200,
        ),
        3.0,
      );
    });

    test('é nula enquanto o servidor não calculou a indisponibilidade', () {
      expect(
        ServiceTimeMetrics.downtimeToServiceRatio(
          downtimeMinutes: null,
          serviceMinutes: 200,
        ),
        isNull,
      );
    });

    test('é nula quando não há tempo técnico (evita divisão por zero)', () {
      expect(
        ServiceTimeMetrics.downtimeToServiceRatio(
          downtimeMinutes: 600,
          serviceMinutes: 0,
        ),
        isNull,
      );
    });
  });
}
