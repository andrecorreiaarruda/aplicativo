import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.value, this.compact = false});

  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata(value);
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

  static _StatusMetadata _metadata(String value) {
    switch (value) {
      case 'operational':
        return const _StatusMetadata('Operacional', OrionColors.success);
      case 'degraded':
        return const _StatusMetadata('Degradado', OrionColors.warning);
      case 'stopped':
        return const _StatusMetadata('Parado', OrionColors.danger);
      case 'decommissioned':
        return const _StatusMetadata('Desativado', OrionColors.muted);
      case 'open':
        return const _StatusMetadata('Aberto', OrionColors.blue);
      case 'diagnosing':
        return const _StatusMetadata('Em andamento', OrionColors.warning);
      case 'waiting_parts':
        return const _StatusMetadata('Aguardando peça', Color(0xFF8C4A00));
      case 'waiting_customer':
        return const _StatusMetadata('Aguardando cliente', Color(0xFF6B4EFF));
      case 'resolved':
        return const _StatusMetadata('Concluído', OrionColors.success);
      case 'cancelled':
        return const _StatusMetadata('Cancelado', OrionColors.muted);
      case 'reviewed':
        return const _StatusMetadata('Revisada', OrionColors.navy);
      case 'recurring':
        return const _StatusMetadata('Recorrente', OrionColors.blue);
      case 'confirmed':
        return const _StatusMetadata('Confirmada', OrionColors.success);
      case 'probable':
        return const _StatusMetadata('Provável', OrionColors.warning);
      case 'obsolete':
        return const _StatusMetadata('Obsoleta', OrionColors.danger);
      default:
        return const _StatusMetadata('Não confirmada', OrionColors.muted);
    }
  }
}

class _StatusMetadata {
  const _StatusMetadata(this.label, this.color);
  final String label;
  final Color color;
}
