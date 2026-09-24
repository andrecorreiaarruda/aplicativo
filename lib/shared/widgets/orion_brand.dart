import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';

class OrionBrand extends StatelessWidget {
  const OrionBrand({
    super.key,
    this.compact = false,
    this.showProductDetails = true,
    this.onDark = false,
    this.height = 38,
  });

  final bool compact;
  final bool showProductDetails;
  final bool onDark;
  final double height;

  /// Versão branca da logo, com fundo transparente, para fundo escuro.
  ///
  /// A logo é um JPG de fundo branco, sem transparência. Em vez de manter
  /// um segundo arquivo que teria de acompanhar cada mudança da logo, a
  /// versão escura é derivada desta na hora de desenhar: toda a cor vira
  /// branco, e a opacidade passa a vir do quanto o ponto é escuro. O fundo
  /// branco some, o texto azul-marinho fica branco sólido, e as linhas
  /// azul-claras da lâmpada ficam brancas translúcidas — mantendo a
  /// graduação do desenho original.
  ///
  /// Opacidade = 520 − 0,7 × (R + G + B), na escala de 0 a 255, para pontos
  /// opacos. O deslocamento de 520 zera também os quase-brancos que a
  /// compressão JPG deixa ao redor do desenho, que de outro modo virariam
  /// um halo sobre o escuro.
  ///
  /// A opacidade original entra na conta (2,1 × A − 535,5 no lugar de 520)
  /// por causa da sobra transparente ao redor da imagem, quando ela não
  /// preenche a caixa: ali o ponto é (0, 0, 0, 0), e sem esse termo o
  /// "preto" transparente viraria uma moldura branca. Para ponto opaco,
  /// 2,1 × 255 − 535,5 = 0, e a fórmula volta a ser a de cima.
  static const _logoBranca = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    -0.7, -0.7, -0.7, 2.1, -15.5,
  ]);

  @override
  Widget build(BuildContext context) {
    // Fundo escuro pode vir de dois lugares: o modo escuro do aplicativo,
    // ou um painel escuro dentro do modo claro, como o da tela de login.
    final sobreFundoEscuro =
        onDark || Theme.of(context).brightness == Brightness.dark;
    final textColor = onDark ? Colors.white : context.orion.emphasis;
    final showDetails = !compact && showProductDetails;

    Widget logo = Image.asset(
      compact
          ? 'assets/branding/orion-icon.png'
          : 'assets/branding/orion-logo.jpg',
      height: height,
      width: compact ? height : height * 2.55,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.lightbulb_outline_rounded,
        color: onDark ? context.orion.accentBright : context.orion.accent,
        size: height,
      ),
    );
    if (sobreFundoEscuro) {
      logo = ColorFiltered(colorFilter: _logoBranca, child: logo);
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: logo),
        if (showDetails) ...[
          const SizedBox(width: 10),
          Container(width: 1, height: height * .7, color: context.orion.border),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ServiceLog AI',
                maxLines: 1,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Engenharia clínica',
                maxLines: 1,
                style: TextStyle(
                  color: onDark
                      ? const Color(0xFFB9C8E8)
                      : context.orion.textMuted,
                  fontSize: 10.5,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (!showDetails) return content;

    // Em barras e painéis estreitos, reduz somente a composição completa da
    // marca. O logotipo isolado e o ícone permanecem em tamanho nominal.
    return SizedBox(
      height: height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: content,
      ),
    );
  }
}
