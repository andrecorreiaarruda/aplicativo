import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';

/// Confirmação de exclusão definitiva.
///
/// Aqui a palavra "excluir" é literal, ao contrário de [confirmArchive]: a
/// linha sai do banco e não há como trazê-la de volta. O texto diz isso
/// sem rodeio, e o botão nomeia o que faz — um "Confirmar" genérico
/// esconderia justamente o que precisa ficar visível.
Future<bool> confirmPurge(
  BuildContext context, {
  required String tipo,
  required String nome,
}) async {
  final resposta = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.delete_forever_rounded, color: OrionColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Text('Excluir $tipo para sempre?')),
        ],
      ),
      content: Text(
        '"$nome" será apagado do banco, aqui e no servidor.\n\n'
        'Não há como desfazer, e a restauração deixa de ser possível. '
        'A exclusão é recusada se algum registro ainda depender deste.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OrionColors.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Excluir para sempre'),
        ),
      ],
    ),
  );
  return resposta ?? false;
}
