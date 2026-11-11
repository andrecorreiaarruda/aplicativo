import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';

/// Lista de registros numa caixa só, com uma linha fina entre os itens.
///
/// Substitui a grade de cartões das listagens: cada cartão tinha borda,
/// cantos, sombra e um ícone num quadrado colorido, repetidos centenas de
/// vezes. Em linhas cabe o triplo na tela, e o olho corre a lista de cima
/// para baixo, que é como se procura um registro.
///
/// [header] e [footer] rolam junto com a lista. Os itens são montados sob
/// demanda: com três mil atendimentos, só os que aparecem na tela existem.
class RecordList extends StatelessWidget {
  const RecordList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.header = const [],
    this.empty,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 32),
    this.onRefresh,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Título, busca e filtros, acima da lista.
  final List<Widget> header;

  /// Mostrado no lugar da caixa quando não há itens.
  final Widget? empty;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: context.orion.border);
    final radius = Radius.circular(OrionTheme.radiusLarge);
    final list = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            0,
          ),
          sliver: SliverList.list(children: header),
        ),
        if (itemCount == 0)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: padding.horizontal / 2),
            sliver: SliverToBoxAdapter(child: empty ?? const SizedBox()),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              0,
              padding.right,
              padding.bottom,
            ),
            sliver: SliverList.builder(
              itemCount: itemCount,
              itemBuilder: (context, index) {
                final first = index == 0;
                final last = index == itemCount - 1;
                // A caixa é desenhada linha a linha: as bordas laterais em
                // todas, a de cima só na primeira e a de baixo em todas —
                // que vira o separador. Assim a lista continua preguiçosa.
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.orion.surface,
                    border: Border(
                      left: border,
                      right: border,
                      top: first ? border : BorderSide.none,
                      bottom: border,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: first ? radius : Radius.zero,
                      bottom: last ? radius : Radius.zero,
                    ),
                  ),
                  child: itemBuilder(context, index),
                );
              },
            ),
          ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Texto pequeno e apagado, para a segunda linha de um registro.
class MetaText extends StatelessWidget {
  const MetaText(this.text, {super.key, this.maxLines = 1});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.orion.textMuted, fontSize: 13),
    );
  }
}
