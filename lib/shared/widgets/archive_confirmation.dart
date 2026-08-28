import 'package:flutter/material.dart';

/// Confirmação de arquivamento.
///
/// O texto evita a palavra "excluir": arquivar não apaga nada, e prometer
/// exclusão seria mentira sobre o que o botão faz.
Future<bool> confirmArchive(
  BuildContext context, {
  required String tipo,
  required String nome,
}) async {
  final resposta = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Arquivar $tipo?'),
      content: Text(
        '"$nome" sairá das listagens, mas continuará no banco e poderá ser '
        'restaurado em Arquivados.\n\n'
        'O arquivamento é recusado se houver histórico dependente.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Arquivar'),
        ),
      ],
    ),
  );
  return resposta ?? false;
}
