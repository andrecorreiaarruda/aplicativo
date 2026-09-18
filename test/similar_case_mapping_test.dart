import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/data/repositories/supabase_service_log_repository.dart';

Map<String, dynamic> _baseJson() => {
  'service_case_id': 'case-1',
  'case_number': 42,
  'equipment_id': 'eq-1',
  'manufacturer': 'Philips',
  'equipment_model': 'Allura Xper FD10',
  'serial_number': 'SN-001',
  'activity_type': 'maintenance',
  'opened_at': '2026-06-01T10:00:00Z',
  'reported_failure': 'Falha de aquisição',
  'error_code': 'XPER-ACQ-42',
  'subsystem': 'Cadeia de aquisição',
  'solution_confidence': 'unconfirmed',
  'exact_code_match': false,
  'lexical_score': 0.0,
  'vector_similarity': 0.0,
  'final_score': 0.5,
};

void main() {
  test('preenche explanation quando ai_explanation vem preenchido', () {
    final json = _baseJson()
      ..['ai_explanation'] =
          'Mesmo código de erro e mesmo subsistema da falha atual.';

    final result = SupabaseServiceLogRepository.mapSimilarCaseJson(json);

    expect(
      result.explanation,
      'Mesmo código de erro e mesmo subsistema da falha atual.',
    );
  });

  test('explanation fica nula quando ai_explanation está ausente', () {
    final result = SupabaseServiceLogRepository.mapSimilarCaseJson(_baseJson());

    expect(result.explanation, isNull);
  });

  test('explanation fica nula quando ai_explanation é string vazia', () {
    final json = _baseJson()..['ai_explanation'] = '';

    final result = SupabaseServiceLogRepository.mapSimilarCaseJson(json);

    expect(result.explanation, isNull);
  });

  test('reasons combina os sinais determinísticos existentes', () {
    final json = _baseJson()
      ..['exact_code_match'] = true
      ..['lexical_score'] = 0.4
      ..['vector_similarity'] = 0.9
      ..['solution_confidence'] = 'confirmed';

    final result = SupabaseServiceLogRepository.mapSimilarCaseJson(json);

    expect(
      result.reasons,
      containsAll(<String>[
        'Código de erro idêntico',
        'Descrição textual semelhante',
        'Alta similaridade semântica',
        'Solução validada',
      ]),
    );
  });
}
