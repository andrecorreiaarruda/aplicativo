import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/equipment.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/purge_confirmation.dart';
import '../../shared/widgets/section_header.dart';
import '../shell/service_log_controller.dart';

/// Registros arquivados, com restauração.
///
/// Arquivar não apaga: o registro sai das listagens e continua no banco,
/// preservando o histórico técnico. Esta página é o caminho de volta.
class ArchivedPage extends StatefulWidget {
  const ArchivedPage({super.key, required this.controller});

  final ServiceLogController controller;

  @override
  State<ArchivedPage> createState() => _ArchivedPageState();
}

class _ArchivedPageState extends State<ArchivedPage> {
  late Future<ArchivedRecords> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.fetchArchived();
  }

  void _recarregar() {
    // Bloco, não seta: uma seta devolveria o Future atribuído, e o Flutter
    // recusa um callback de setState que retorna Future.
    final proximo = widget.controller.fetchArchived();
    setState(() {
      _future = proximo;
    });
  }

  Future<void> _restaurar(Future<bool> Function() acao) async {
    final ok = await acao();
    if (!mounted) return;
    if (ok) {
      _recarregar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Registro restaurado.')));
    } else {
      final motivo =
          widget.controller.errorMessage ?? 'Não foi possível restaurar.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(motivo)));
    }
  }

  Future<void> _excluir({
    required String tipo,
    required String nome,
    required Future<bool> Function() acao,
  }) async {
    final confirmado = await confirmPurge(context, tipo: tipo, nome: nome);
    if (!confirmado || !mounted) return;
    final ok = await acao();
    if (!mounted) return;
    _recarregar();
    final mensagem = ok
        ? 'Registro excluído em definitivo.'
        : widget.controller.errorMessage ?? 'Não foi possível excluir.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ArchivedRecords>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Não foi possível carregar os arquivados',
            message:
                'A lista completa de arquivados vem do servidor. '
                'Verifique a conexão e tente novamente.',
            action: FilledButton.tonal(
              onPressed: _recarregar,
              child: const Text('Tentar novamente'),
            ),
          );
        }

        final dados = snapshot.data ?? ArchivedRecords.empty;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Arquivados',
                subtitle: dados.isEmpty
                    ? null
                    : dados.total == 1
                    ? '1 registro'
                    : '${dados.total} registros',
                action: IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _recarregar,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              const SizedBox(height: 16),
              if (dados.isEmpty)
                const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Nada arquivado',
                  message:
                      'Cliente, equipamento ou atendimento arquivado aparece '
                      'aqui e pode ser restaurado. Arquivar não apaga o '
                      'histórico.',
                ),
              if (dados.customers.isNotEmpty)
                _Grupo(
                  titulo: 'Clientes',
                  itens: [
                    for (final item in dados.customers)
                      _LinhaArquivada(
                        titulo: item.name,
                        detalhe: item.locationLabel,
                        arquivadoEm: item.archivedAt,
                        onRestaurar: () => _restaurar(
                          () => widget.controller.restoreCustomer(item.id),
                        ),
                        onExcluir: () => _excluir(
                          tipo: 'cliente',
                          nome: item.name,
                          acao: () => widget.controller.purgeCustomer(item.id),
                        ),
                      ),
                  ],
                ),
              if (dados.equipment.isNotEmpty)
                _Grupo(
                  titulo: 'Equipamentos',
                  itens: [
                    for (final item in dados.equipment)
                      _LinhaArquivada(
                        titulo: item.displayName,
                        detalhe: item.serialLabel,
                        arquivadoEm: item.archivedAt,
                        onRestaurar: () => _restaurar(
                          () => widget.controller.restoreEquipment(item.id),
                        ),
                        onExcluir: () => _excluir(
                          tipo: 'equipamento',
                          nome: '${item.displayName} · ${item.serialLabel}',
                          acao: () => widget.controller.purgeEquipment(item.id),
                        ),
                      ),
                  ],
                ),
              if (dados.cases.isNotEmpty)
                _Grupo(
                  titulo: 'Atendimentos',
                  itens: [
                    for (final item in dados.cases)
                      _LinhaArquivada(
                        titulo:
                            'OS ${item.caseNumber} · ${item.reportedFailure}',
                        detalhe: item.equipmentLabel,
                        arquivadoEm: item.archivedAt,
                        onRestaurar: () => _restaurar(
                          () => widget.controller.restoreCase(item.id),
                        ),
                        onExcluir: () => _excluir(
                          tipo: 'atendimento',
                          nome: 'OS ${item.caseNumber}',
                          acao: () => widget.controller.purgeCase(item.id),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Grupo extends StatelessWidget {
  const _Grupo({required this.titulo, required this.itens});

  final String titulo;
  final List<Widget> itens;

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$titulo · ${itens.length}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(OrionTheme.radiusLarge),
            ),
            child: Column(
              children: [
                for (final (index, item) in itens.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  item,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaArquivada extends StatelessWidget {
  const _LinhaArquivada({
    required this.titulo,
    required this.detalhe,
    required this.arquivadoEm,
    required this.onRestaurar,
    required this.onExcluir,
  });

  final String titulo;
  final String detalhe;
  final DateTime? arquivadoEm;
  final VoidCallback onRestaurar;
  final VoidCallback onExcluir;

  @override
  Widget build(BuildContext context) {
    final quando = arquivadoEm;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      title: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (detalhe.isNotEmpty) detalhe,
          if (quando != null)
            'Arquivado em ${quando.day.toString().padLeft(2, '0')}/'
                '${quando.month.toString().padLeft(2, '0')}/${quando.year}',
        ].join(' · '),
        style: TextStyle(color: context.orion.textMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onRestaurar, child: const Text('Restaurar')),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Excluir para sempre',
            onPressed: onExcluir,
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: context.orion.danger,
            ),
          ),
        ],
      ),
    );
  }
}
