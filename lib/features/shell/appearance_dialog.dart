import 'package:flutter/material.dart';

import '../../core/theme/appearance_controller.dart';

/// Rótulo curto da escolha atual, para o menu da conta.
String appearanceLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Claro',
  ThemeMode.dark => 'Escuro',
  ThemeMode.system => 'Sistema',
};

/// Seletor de aparência.
///
/// A troca vale no mesmo instante, com o diálogo ainda aberto: dá para
/// comparar os três modos antes de fechar, sem botão de confirmar.
Future<void> showAppearanceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final appearance = AppearanceScope.maybeOf(context);
      if (appearance == null) return const SizedBox.shrink();
      return AlertDialog(
        title: const Text('Aparência'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded),
                    label: Text('Sistema'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded),
                    label: Text('Claro'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded),
                    label: Text('Escuro'),
                  ),
                ],
                selected: {appearance.mode},
                onSelectionChanged: (values) =>
                    appearance.setMode(values.first),
              ),
              const SizedBox(height: 14),
              Text(
                appearance.mode == ThemeMode.system
                    ? 'Segue a configuração de claro ou escuro do sistema '
                          'operacional.'
                    : 'Vale só para este computador, e é lembrada na próxima '
                          'vez que o aplicativo abrir.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      );
    },
  );
}
