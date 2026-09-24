import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'service_order.dart';

/// Fontes e logo da OS. Carregados à parte para que os testes possam
/// lê-los do disco, sem o `rootBundle` do aplicativo.
class ServiceOrderAssets {
  const ServiceOrderAssets({
    required this.regular,
    required this.bold,
    required this.logo,
  });

  final pw.Font regular;
  final pw.Font bold;
  final Uint8List logo;

  static Future<ServiceOrderAssets> load() async {
    // Em sequência, sem `Future.wait`: o pacote de recursos pode responder
    // com um `SynchronousFuture`, e o `Future.wait` se perde com eles —
    // devolve a lista vazia. São três leituras locais; não há o que ganhar
    // em paralelo.
    final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final logo = await rootBundle.load('assets/branding/orion-logo.jpg');
    return ServiceOrderAssets(
      regular: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      logo: logo.buffer.asUint8List(logo.offsetInBytes, logo.lengthInBytes),
    );
  }
}

// Cores da marca no modo claro. O PDF é sempre claro: vai para impressão
// e para a caixa de entrada de quem não usa o aplicativo.
const _navy = PdfColor.fromInt(0xFF071A4B);
const _blue = PdfColor.fromInt(0xFF087AA6);
const _ink = PdfColor.fromInt(0xFF14213D);
const _muted = PdfColor.fromInt(0xFF61708C);
const _border = PdfColor.fromInt(0xFFD9E2EF);
const _panel = PdfColor.fromInt(0xFFF4F7FB);

final _dateTime = DateFormat('dd/MM/yyyy HH:mm');
final _date = DateFormat('dd/MM/yyyy');
final _time = DateFormat('HH:mm');

Future<Uint8List> buildServiceOrderPdf(
  ServiceOrder order,
  ServiceOrderAssets assets,
) {
  final document = pw.Document(
    title: 'OS ${order.caseNumber}',
    author: order.issuerName,
    creator: 'ORION ServiceLog',
    subject: 'Ordem de serviço ${order.caseNumber} — ${order.activityLabel}',
  );

  document.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        theme: pw.ThemeData.withFont(base: assets.regular, bold: assets.bold)
            .copyWith(
              defaultTextStyle: pw.TextStyle(
                font: assets.regular,
                fontBold: assets.bold,
                fontSize: 9.5,
                color: _ink,
                lineSpacing: 1.5,
              ),
            ),
      ),
      header: (context) =>
          context.pageNumber == 1 ? pw.SizedBox() : _continuationHeader(order),
      footer: (context) => _footer(order, context),
      build: (context) => [
        _header(order, assets),
        pw.SizedBox(height: 14),
        _summaryStrip(order),
        pw.SizedBox(height: 14),
        _parties(order),
        for (final section in order.sections) ..._section(section),
        if (order.sessions.isNotEmpty) ..._sessions(order),
        ..._times(order),
      ],
    ),
  );

  return document.save();
}

pw.Widget _header(ServiceOrder order, ServiceOrderAssets assets) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Image(pw.MemoryImage(assets.logo), height: 40),
      pw.Spacer(),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'ORDEM DE SERVIÇO',
            style: pw.TextStyle(
              fontSize: 9,
              color: _muted,
              letterSpacing: 1.2,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'Nº ${order.caseNumber}',
            style: pw.TextStyle(
              fontSize: 22,
              color: _navy,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            order.organizationName,
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _continuationHeader(ServiceOrder order) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _border)),
    ),
    child: pw.Row(
      children: [
        pw.Text(
          'Ordem de serviço nº ${order.caseNumber}',
          style: pw.TextStyle(color: _navy, fontWeight: pw.FontWeight.bold),
        ),
        pw.Spacer(),
        pw.Text(
          'continuação',
          style: const pw.TextStyle(color: _muted, fontSize: 8.5),
        ),
      ],
    ),
  );
}

pw.Widget _footer(ServiceOrder order, pw.Context context) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 12),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _border)),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            'Emitida em ${_dateTime.format(order.issuedAt)} por '
            '${order.issuerName} · ORION ServiceLog',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );
}

/// Faixa com o que se quer saber de relance: o que foi feito, em que pé
/// está e quando.
pw.Widget _summaryStrip(ServiceOrder order) {
  final cells = [
    ('Atividade', order.activityLabel),
    ('Situação', order.statusLabel),
    ('Abertura', _dateTime.format(order.openedAt)),
    (
      'Conclusão',
      order.closedAt == null ? '—' : _dateTime.format(order.closedAt!),
    ),
  ];
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: pw.BoxDecoration(
      color: _panel,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      children: [
        for (final (label, value) in cells)
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _label(label),
                pw.SizedBox(height: 2),
                pw.Text(
                  value,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

pw.Widget _parties(ServiceOrder order) {
  pw.Widget box(String title, List<ServiceOrderField> fields) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle(title),
          if (fields.isEmpty)
            pw.Text('Não informado.', style: const pw.TextStyle(color: _muted)),
          for (final field in fields)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [_label(field.label), pw.Text(field.value)],
              ),
            ),
        ],
      ),
    );
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: box('Cliente', order.customerFields)),
      pw.SizedBox(width: 12),
      pw.Expanded(child: box('Equipamento', order.equipmentFields)),
    ],
  );
}

/// Cada campo é devolvido como filhos soltos, e não dentro de uma coluna:
/// o MultiPage só quebra a página entre filhos diretos, e uma solução
/// longa precisa poder continuar na folha seguinte.
List<pw.Widget> _section(ServiceOrderSection section) {
  return [
    _sectionTitle(section.title),
    for (final field in section.fields) ...[
      _label(field.label),
      pw.SizedBox(height: 2),
      pw.Paragraph(
        text: field.value,
        style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
        textAlign: pw.TextAlign.left,
        margin: const pw.EdgeInsets.only(bottom: 9),
      ),
    ],
  ];
}

/// Uma lista, e não uma tabela: a linha de uma tabela não se divide
/// entre páginas, e o relato de um dia de trabalho pode ser longo.
List<pw.Widget> _sessions(ServiceOrder order) {
  String when(ServiceOrderSession session) {
    final end = session.end == null
        ? 'em aberto'
        : _sameDay(session.start, session.end!)
        ? _time.format(session.end!)
        : _dateTime.format(session.end!);
    final minutes = session.minutes;
    return [
      _date.format(session.start),
      '${_time.format(session.start)} – $end',
      if (minutes != null) ServiceOrder.formatMinutes(minutes),
    ].join('   ·   ');
  }

  return [
    _sectionTitle('Sessões de trabalho'),
    for (final session in order.sessions) ...[
      pw.Text(
        when(session),
        style: pw.TextStyle(
          fontSize: 8.5,
          color: _navy,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Paragraph(
        text: session.description.isEmpty ? '—' : session.description,
        style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2),
        textAlign: pw.TextAlign.left,
        margin: const pw.EdgeInsets.only(bottom: 5),
      ),
      pw.Divider(color: _border, thickness: .6, height: 10),
    ],
  ];
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

List<pw.Widget> _times(ServiceOrder order) {
  final cells = [
    ('Tempo técnico', ServiceOrder.formatMinutes(order.serviceMinutes)),
    if (order.downtimeMinutes != null)
      (
        'Indisponibilidade do equipamento',
        ServiceOrder.formatMinutes(order.downtimeMinutes!),
      ),
  ];
  return [
    pw.SizedBox(height: 14),
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: pw.BoxDecoration(
        color: _panel,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: [
          for (final (label, value) in cells)
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _label(label),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    value,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  ];
}

pw.Widget _sectionTitle(String title) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
    padding: const pw.EdgeInsets.only(bottom: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 1.2)),
    ),
    child: pw.Text(
      title.toUpperCase(),
      style: pw.TextStyle(
        color: _navy,
        fontSize: 10,
        letterSpacing: .8,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _boxTitle(String title) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      title.toUpperCase(),
      style: pw.TextStyle(
        color: _navy,
        fontSize: 9,
        letterSpacing: .8,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _label(String text) {
  return pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 8,
      color: _muted,
      fontWeight: pw.FontWeight.bold,
    ),
  );
}
