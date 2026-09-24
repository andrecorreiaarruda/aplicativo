import 'package:flutter/material.dart';

/// Campo de formulário com o nome escrito acima da caixa.
///
/// Substitui o rótulo flutuante do Material, que começa dentro da caixa e,
/// ao receber o foco, sobe e encolhe. O movimento distrai, e o rótulo
/// reduzido fica difícil de ler. Aqui o nome fica sempre no mesmo lugar e
/// no mesmo tamanho, esteja o campo vazio, preenchido ou em edição.
///
/// Esconder o nome como um texto de exemplo, que some ao digitar, seria a
/// alternativa mais simples — mas numa tela de edição, com tudo
/// preenchido, nenhum campo diria o que é.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;

  /// O campo em si, sem `labelText` na decoração.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Leitores de tela anunciam nome e campo juntos, como fariam com o
    // rótulo interno que este componente substitui.
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
