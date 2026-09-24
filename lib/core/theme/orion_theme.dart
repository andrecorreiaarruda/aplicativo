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

  static const light = OrionPalette(
    emphasis: OrionColors.navy,
    brandDeep: OrionColors.deepNavy,
    accent: OrionColors.blue,
    accentBright: OrionColors.cyan,
    accentSoft: OrionColors.paleCyan,
    surface: Colors.white,
    panel: OrionColors.canvas,
    canvas: OrionColors.canvas,
    text: OrionColors.ink,
    textMuted: OrionColors.muted,
    border: OrionColors.border,
    success: OrionColors.success,
    warning: OrionColors.warning,
    danger: OrionColors.danger,
    onEmphasis: Colors.white,
  );

  /// Modo escuro. Os tons de alerta são mais claros que os do modo claro:
  /// o vermelho e o laranja originais foram escolhidos para fundo branco e
  /// ficam abaixo do contraste mínimo de leitura sobre fundo escuro.
  static const dark = OrionPalette(
    emphasis: Color(0xFFD7E4FF),
    brandDeep: Color(0xFF030B1F),
    accent: Color(0xFF4CC3E6),
    accentBright: Color(0xFF3FD0E8),
    accentSoft: Color(0xFF12303F),
    surface: Color(0xFF111B2E),
    panel: Color(0xFF0C1526),
    canvas: Color(0xFF080F1E),
    text: Color(0xFFE4EBF7),
    textMuted: Color(0xFF9AA9C4),
    border: Color(0xFF26354F),
    success: Color(0xFF5CD69B),
    warning: Color(0xFFF2AE5C),
    danger: Color(0xFFFF8A7A),
    onEmphasis: Color(0xFF071A4B),
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
          secondary: p.accentBright,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.textMuted,
          outline: p.border,
          outlineVariant: p.border,
          error: p.danger,
        );

    // Botão principal: azul-marinho sólido no claro. No escuro, um marinho
    // sobre o fundo quase preto não se destacaria; o azul de ação sim.
    final filledBackground = isDark ? p.accent : p.emphasis;
    final filledForeground = isDark ? p.canvas : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.emphasis,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        alignLabelWithHint: true,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.brandDeep,
        indicatorColor: OrionColors.cyan,
        selectedIconTheme: const IconThemeData(color: OrionColors.deepNavy),
        unselectedIconTheme: const IconThemeData(color: Color(0xFFB9C8E8)),
        selectedLabelTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: Color(0xFFB9C8E8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: filledBackground,
          foregroundColor: filledForeground,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.emphasis,
          minimumSize: const Size(0, 46),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? p.accent : p.emphasis,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: filledBackground,
        foregroundColor: filledForeground,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? p.emphasis : p.brandDeep,
        contentTextStyle: TextStyle(color: isDark ? p.canvas : Colors.white),
      ),
      dividerTheme: DividerThemeData(color: p.border),
    );
  }
}
