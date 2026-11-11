import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';

/// Título da página, com as ações à direita.
///
/// O subtítulo é opcional e deve dizer algo que a pessoa não saiba: uma
/// contagem, um filtro ativo. As frases que explicavam cada tela ("Cadastro
/// rápido de hospitais...") saíram — quem usa todo dia já sabe o que é.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: TextStyle(color: context.orion.textMuted, fontSize: 13),
          ),
        ],
      ],
    );

    if (action == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), action!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            action!,
          ],
        );
      },
    );
  }
}
