import 'package:flutter/material.dart';

/// Cores de referência da marca, no modo claro.
///
/// As telas não devem usar estas constantes: elas não mudam com o tema, e
/// um texto em azul-marinho fixo some sobre o fundo escuro. As telas pedem
/// a cor pelo papel que ela cumpre, em `context.orion` ([OrionPalette]).
/// Estas ficam para o construtor do tema e para a tela de falha fatal, que
/// é desenhada antes de haver tema.
abstract final class OrionColors {
  static const navy = Color(0xFF071A4B);
  static const deepNavy = Color(0xFF041132);
  static const blue = Color(0xFF087AA6);
  static const cyan = Color(0xFF18A9C4);
  static const paleCyan = Color(0xFFE8F7FA);
  static const canvas = Color(0xFFF4F7FB);
  static const ink = Color(0xFF14213D);
  static const muted = Color(0xFF61708C);
  static const border = Color(0xFFD9E2EF);
  static const success = Color(0xFF18794E);
  static const warning = Color(0xFFA45B00);
  static const danger = Color(0xFFB42318);
}

/// Paleta ORION por papel, com uma versão para cada modo.
///
/// Os nomes dizem para que a cor serve, e não qual é: no modo escuro o
/// "destaque" deixa de ser azul-marinho e passa a ser um azul quase branco,
/// porque é isso que se lê sobre fundo escuro. Um nome como `navy` levaria
/// a usar a cor errada justamente onde ela mais importa.
@immutable
class OrionPalette extends ThemeExtension<OrionPalette> {
  const OrionPalette({
    required this.emphasis,
    required this.brandDeep,
    required this.accent,
    required this.accentBright,
    required this.accentSoft,
    required this.surface,
    required this.panel,
    required this.canvas,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.success,
    required this.warning,
    required this.danger,
    required this.onEmphasis,
  });

  /// Texto e ícone de destaque: títulos de cartão, rótulos de chip, valores.
  final Color emphasis;

  /// Fundo institucional escuro — barra lateral e painel da tela de login.
  /// Continua escuro nos dois modos.
  final Color brandDeep;

  /// Azul de ação: links, ícones ativos, borda do campo em foco.
  final Color accent;

  /// Ciano da marca, para detalhes sobre fundo escuro.
  final Color accentBright;

  /// Fundo suave de avisos, etiquetas e ícones em destaque.
  final Color accentSoft;

  /// Fundo de cartões, diálogos e campos.
  final Color surface;

  /// Fundo de blocos internos a um cartão, um tom abaixo de [surface].
  final Color panel;

  /// Fundo da janela.
  final Color canvas;

  final Color text;
  final Color textMuted;
  final Color border;
  final Color success;
  final Color warning;
  final Color danger;

  /// Texto sobre um fundo [emphasis], como as iniciais no avatar.
  final Color onEmphasis;

  // Cinzas neutros, sem o azulado que dava a tudo o mesmo tom de painel
  // de controle. O azul-marinho da marca fica para o que precisa de
  // destaque de fato: o botão principal, o item selecionado, os números.
  static const light = OrionPalette(
    emphasis: OrionColors.navy,
    brandDeep: OrionColors.deepNavy,
    accent: Color(0xFF1E5E9E),
    accentBright: OrionColors.cyan,
    accentSoft: Color(0xFFEDF2F7),
    surface: Colors.white,
    panel: Color(0xFFF7F8FA),
    canvas: Color(0xFFF3F4F6),
    text: Color(0xFF1D232B),
    textMuted: Color(0xFF5F6874),
    border: Color(0xFFE1E4E8),
    success: Color(0xFF1E7A4C),
    warning: Color(0xFF9A5B00),
    danger: OrionColors.danger,
    onEmphasis: Colors.white,
  );

  /// Modo escuro. Os tons de alerta são mais claros que os do modo claro:
  /// o vermelho e o laranja originais foram escolhidos para fundo branco e
  /// ficam abaixo do contraste mínimo de leitura sobre fundo escuro.
  static const dark = OrionPalette(
    emphasis: Color(0xFFE3E7EC),
    brandDeep: Color(0xFF101318),
    accent: Color(0xFF7CB0E6),
    accentBright: Color(0xFF3FD0E8),
    accentSoft: Color(0xFF242B34),
    surface: Color(0xFF1B1E23),
    panel: Color(0xFF20242A),
    canvas: Color(0xFF15171B),
    text: Color(0xFFE3E7EC),
    textMuted: Color(0xFF9AA2AD),
    border: Color(0xFF2E333A),
    success: Color(0xFF5CC992),
    warning: Color(0xFFE3A55A),
    danger: Color(0xFFF08A7E),
    onEmphasis: Color(0xFF15171B),
  );

  @override
  OrionPalette copyWith({
    Color? emphasis,
    Color? brandDeep,
    Color? accent,
    Color? accentBright,
    Color? accentSoft,
    Color? surface,
    Color? panel,
    Color? canvas,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? success,
    Color? warning,
    Color? danger,
    Color? onEmphasis,
  }) => OrionPalette(
    emphasis: emphasis ?? this.emphasis,
    brandDeep: brandDeep ?? this.brandDeep,
    accent: accent ?? this.accent,
    accentBright: accentBright ?? this.accentBright,
    accentSoft: accentSoft ?? this.accentSoft,
    surface: surface ?? this.surface,
    panel: panel ?? this.panel,
    canvas: canvas ?? this.canvas,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    border: border ?? this.border,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    onEmphasis: onEmphasis ?? this.onEmphasis,
  );

  @override
  OrionPalette lerp(OrionPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return OrionPalette(
      emphasis: mix(emphasis, other.emphasis),
      brandDeep: mix(brandDeep, other.brandDeep),
      accent: mix(accent, other.accent),
      accentBright: mix(accentBright, other.accentBright),
      accentSoft: mix(accentSoft, other.accentSoft),
      surface: mix(surface, other.surface),
      panel: mix(panel, other.panel),
      canvas: mix(canvas, other.canvas),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      border: mix(border, other.border),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      onEmphasis: mix(onEmphasis, other.onEmphasis),
    );
  }
}

extension OrionThemeContext on BuildContext {
  /// Paleta do tema em vigor. Sempre presente: os dois temas a registram.
  OrionPalette get orion =>
      Theme.of(this).extension<OrionPalette>() ?? OrionPalette.light;
}

abstract final class OrionTheme {
  static ThemeData light() => _build(OrionPalette.light, Brightness.light);

  static ThemeData dark() => _build(OrionPalette.dark, Brightness.dark);

  /// Cantos. Pequenos de propósito: cartões muito arredondados, com
  /// sombra e ícone colorido em cada canto, eram o que mais fazia o
  /// aplicativo parecer genérico.
  static const radius = 6.0;
  static const radiusLarge = 8.0;

  /// Um único construtor para os dois modos. Manter dois temas escritos à
  /// mão faria cada ajuste futuro de espaçamento ou raio ser feito duas
  /// vezes — e cedo ou tarde um dos dois ficaria para trás.
  static ThemeData _build(OrionPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: OrionColors.blue,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? p.accent : p.emphasis,
          onPrimary: isDark ? p.canvas : Colors.white,
          secondary: p.accent,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.textMuted,
          surfaceContainerHighest: p.panel,
          surfaceContainerHigh: p.panel,
          surfaceContainer: p.panel,
          surfaceContainerLow: p.surface,
          surfaceContainerLowest: p.surface,
          secondaryContainer: p.accentSoft,
          onSecondaryContainer: p.text,
          outline: p.border,
          outlineVariant: p.border,
          error: p.danger,
        );

    final filledBackground = isDark ? p.accent : p.emphasis;
    final filledForeground = isDark ? p.canvas : Colors.white;
    final small = BorderRadius.circular(radius);
    final border = BorderSide(color: p.border);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    // Pesos moderados. O padrão anterior punha w800 em quase todo título,
    // e texto em negrito por toda parte deixa de destacar alguma coisa.
    final text = base.textTheme
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12.5),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        )
        .apply(bodyColor: p.text, displayColor: p.text);

    return base.copyWith(
      textTheme: text,
      extensions: [p],
      scaffoldBackgroundColor: p.canvas,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
        shape: Border(bottom: border),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        hintStyle: text.bodyMedium?.copyWith(
          color: p.textMuted.withValues(alpha: .8),
        ),
        border: OutlineInputBorder(borderRadius: small, borderSide: border),
        enabledBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: border,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
        alignLabelWithHint: true,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: border,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
        titleTextStyle: text.titleLarge,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: small, side: border),
        elevation: 3,
      ),
      // A barra lateral acompanha a superfície, com uma borda à direita.
      // O bloco azul-marinho com pílula ciano chamava mais atenção que o
      // conteúdo.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: small),
        selectedIconTheme: IconThemeData(color: p.emphasis, size: 22),
        unselectedIconTheme: IconThemeData(color: p.textMuted, size: 22),
        // Derivados da tipografia do tema, e não estilos soltos: um
        // TextStyle sem família substitui o do tema por inteiro, e o texto
        // cai na fonte padrão do sistema, diferente do resto da tela.
        selectedLabelTextStyle: text.labelLarge?.copyWith(
          color: p.text,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(
          color: p.textMuted,
          fontWeight: FontWeight.w400,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
        surfaceTintColor: Colors.transparent,
        height: 64,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: filledBackground,
          foregroundColor: filledForeground,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: border,
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textMuted,
          shape: RoundedRectangleBorder(borderRadius: small),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          selectedBackgroundColor: p.accentSoft,
          selectedForegroundColor: p.text,
          foregroundColor: p.textMuted,
          side: border,
          shape: RoundedRectangleBorder(borderRadius: small),
          visualDensity: VisualDensity.compact,
        ),
        // Sem o tique: o fundo já diz qual está escolhido.
        selectedIcon: const SizedBox.shrink(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accentSoft,
        side: border,
        shape: RoundedRectangleBorder(borderRadius: small),
        labelStyle: text.bodyMedium?.copyWith(color: p.text, fontSize: 13),
        showCheckmark: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: filledBackground,
        foregroundColor: filledForeground,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? p.emphasis : p.text,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: isDark ? p.canvas : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: small),
      ),
      dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: small),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: isDark ? p.emphasis : p.text,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: text.bodySmall?.copyWith(
          color: isDark ? p.canvas : Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }
}
