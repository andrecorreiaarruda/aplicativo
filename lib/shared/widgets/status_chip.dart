import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';

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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: metadata.color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: metadata.color.withValues(alpha: .30)),
      ),
      child: Text(
        metadata.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: metadata.color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }

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
