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

  @override
  Widget build(BuildContext context) {
    final textColor = onDark ? Colors.white : OrionColors.navy;
    final showDetails = !compact && showProductDetails;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            compact
                ? 'assets/branding/orion-icon.png'
                : 'assets/branding/orion-logo.jpg',
            height: height,
            width: compact ? height : height * 2.55,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              Icons.lightbulb_outline_rounded,
              color: onDark ? OrionColors.cyan : OrionColors.blue,
              size: height,
            ),
          ),
        ),
        if (showDetails) ...[
          const SizedBox(width: 10),
          Container(width: 1, height: height * .7, color: OrionColors.border),
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
                  color: onDark ? const Color(0xFFB9C8E8) : OrionColors.muted,
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
