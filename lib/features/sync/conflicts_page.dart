import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/sync/sync_conflict.dart';
import '../../shared/widgets/empty_state.dart';
import '../shell/service_log_controller.dart';

/// Tela de resolução de conflitos de sincronização.
///
/// Um conflito acontece quando o mesmo registro foi alterado aqui e no
/// servidor entre duas sincronizações. A operação fica parada na fila — e,
/// enquanto está parada, o download não é aplicado: a fila pendente existe
/// para impedir que o servidor sobreponha alterações locais ainda não
/// enviadas. Por isso um conflito não resolvido congela a entrada de
/// novidades, e não apenas a alteração que o causou.
///
/// Só o usuário sabe qual das duas versões vale. A tela não escolhe por
/// ele; apresenta as duas saídas e o que cada uma custa.
Future<void> showConflictsPage(
  BuildContext context,
  ServiceLogController controller,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ConflictsPage(controller: controller)),
  );
}

class ConflictsPage extends StatefulWidget {
  const ConflictsPage({super.key, required this.controller});

  final ServiceLogController controller;

  @override
  State<ConflictsPage> createState() => _ConflictsPageState();
}

class _ConflictsPageState extends State<ConflictsPage> {
  late Future<List<SyncConflict>> _future;
  String? _resolvendo;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.fetchConflicts();
  }

  void _recarregar() {
    // O corpo precisa ser um bloco: uma seta devolveria o próprio Future
    // atribuído, e o Flutter recusa um callback de setState que retorna
    // Future — a ideia é que o trabalho assíncrono aconteça fora dele.
    final proximo = widget.controller.fetchConflicts();
    setState(() {
      _future = proximo;
    });
  }

  Future<void> _resolver(
    SyncConflict conflito,
    ConflictResolution decisao,
  ) async {
    final confirmado = await _confirmar(conflito, decisao);
    if (!confirmado || !mounted) return;

    setState(() => _resolvendo = conflito.operationId);
    final ok = await widget.controller.resolveConflict(
      conflito.operationId,
      decisao,
    );
    if (!mounted) return;
    setState(() => _resolvendo = null);
    _recarregar();

    final mensagem = ok
        ? switch (decisao) {
            ConflictResolution.keepLocal => 'Sua versão foi enviada.',
            ConflictResolution.discardLocal =>
              'Alteração descartada. A versão do servidor volta a valer.',
          }
        : widget.controller.errorMessage ??
              'A decisão foi registrada, mas o envio falhou. '
                  'Será reenviada na próxima sincronização.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<bool> _confirmar(
    SyncConflict conflito,
    ConflictResolution decisao,
  ) async {
    final manter = decisao == ConflictResolution.keepLocal;
    final resposta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          manter ? 'Sobrescrever o servidor?' : 'Descartar sua alteração?',
        ),
        content: Text(
          manter
              ? 'A sua versão de "${conflito.recordLabel}" será gravada por '
                    'cima da que está no servidor.\n\n'
                    'A alteração feita no outro dispositivo será perdida.'
              : 'A sua alteração em "${conflito.recordLabel}" será removida '
                    'da fila e não chegará ao servidor.\n\n'
                    'A versão do outro dispositivo passa a valer aqui também.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(manter ? 'Sobrescrever' : 'Descartar'),
          ),
        ],
      ),
    );
    return resposta ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conflitos de sincronização')),
      body: FutureBuilder<List<SyncConflict>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final conflitos = snapshot.data ?? const <SyncConflict>[];
          if (conflitos.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'Nenhum conflito',
              message:
                  'Todas as alterações locais foram aceitas pelo servidor. '
                  'Quando o mesmo registro for alterado em dois lugares, o '
                  'conflito aparece aqui para você decidir qual versão vale.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            itemCount: conflitos.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              if (index == 0) return _Aviso(total: conflitos.length);
              final conflito = conflitos[index - 1];
              return _ConflictCard(
                conflito: conflito,
                ocupado: _resolvendo != null,
                resolvendo: _resolvendo == conflito.operationId,
                onKeepLocal: () =>
                    _resolver(conflito, ConflictResolution.keepLocal),
                onDiscardLocal: () =>
                    _resolver(conflito, ConflictResolution.discardLocal),
              );
            },
          );
        },
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OrionColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OrionColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sync_problem_rounded, color: OrionColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              total == 1
                  ? 'Uma alteração feita aqui não foi aceita porque o registro '
                        'mudou no servidor. Enquanto ela não for resolvida, '
                        'nenhuma novidade do servidor entra no aplicativo.'
                  : '$total alterações feitas aqui não foram aceitas porque os '
                        'registros mudaram no servidor. Enquanto houver '
                        'conflito, nenhuma novidade do servidor entra no '
                        'aplicativo.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflito,
    required this.ocupado,
    required this.resolvendo,
    required this.onKeepLocal,
    required this.onDiscardLocal,
  });

  final SyncConflict conflito;
  final bool ocupado;
  final bool resolvendo;
  final VoidCallback onKeepLocal;
  final VoidCallback onDiscardLocal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(
                    '${conflito.entityLabel} · ${conflito.actionLabel}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (resolvendo)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              conflito.recordLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(conflito.message, style: theme.textTheme.bodyMedium),
            if (conflito.detectedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Detectado em ${_formatar(conflito.detectedAt!.toLocal())}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: ocupado ? null : onKeepLocal,
                  child: Text(conflito.keepLocalLabel),
                ),
                OutlinedButton(
                  onPressed: ocupado ? null : onDiscardLocal,
                  child: const Text('Descartar a minha versão'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatar(DateTime value) {
    String dois(int valor) => valor.toString().padLeft(2, '0');
    return '${dois(value.day)}/${dois(value.month)}/${value.year} '
        '${dois(value.hour)}:${dois(value.minute)}';
  }
}
