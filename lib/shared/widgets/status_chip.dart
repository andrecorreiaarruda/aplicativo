import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';

/// Situação de um registro: um ponto colorido e o nome.
///
/// Era uma pílula com fundo e borda coloridos. Várias delas lado a lado,
/// em cada cartão, disputavam atenção com o conteúdo; o ponto basta para
/// distinguir as situações e deixa o texto em cor de leitura normal.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.value, this.compact = false});

  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata(
      value,
      context.orion,
      Theme.of(context).brightness == Brightness.dark,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: metadata.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            metadata.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.orion.text,
              fontSize: compact ? 12.5 : 13,
            ),
          ),
        ),
      ],
    );
  }

  /// Só o nome, para textos e buscas.
  static String labelOf(String value) =>
      _metadata(value, OrionPalette.light, false).label;

  static _StatusMetadata _metadata(String value, OrionPalette p, bool escuro) {
    switch (value) {
      case 'operational':
        return _StatusMetadata('Operacional', p.success);
      case 'degraded':
        return _StatusMetadata('Degradado', p.warning);
      case 'stopped':
        return _StatusMetadata('Parado', p.danger);
      case 'decommissioned':
        return _StatusMetadata('Desativado', p.textMuted);
      case 'open':
        return _StatusMetadata('Aberto', p.accent);
      case 'diagnosing':
        return _StatusMetadata('Em andamento', p.warning);
      case 'waiting_parts':
        // Laranja queimado e violeta ficam fora da paleta de propósito: são
        // os dois estados de espera, e precisam se distinguir dos alertas.
        return _StatusMetadata(
          'Aguardando peça',
          escuro ? const Color(0xFFE8A35E) : const Color(0xFF8C4A00),
        );
      case 'waiting_customer':
        return _StatusMetadata(
          'Aguardando cliente',
          escuro ? const Color(0xFFA897FF) : const Color(0xFF6B4EFF),
        );
      case 'resolved':
        return _StatusMetadata('Concluído', p.success);
      case 'cancelled':
        return _StatusMetadata('Cancelado', p.textMuted);
      case 'reviewed':
        return _StatusMetadata('Revisada', p.emphasis);
      case 'recurring':
        return _StatusMetadata('Recorrente', p.accent);
      case 'confirmed':
        return _StatusMetadata('Confirmada', p.success);
      case 'probable':
        return _StatusMetadata('Provável', p.warning);
      case 'obsolete':
        return _StatusMetadata('Obsoleta', p.danger);
      default:
        return _StatusMetadata('Não confirmada', p.textMuted);
    }
  }
}

class _StatusMetadata {
  const _StatusMetadata(this.label, this.color);
  final String label;
  final Color color;
}
