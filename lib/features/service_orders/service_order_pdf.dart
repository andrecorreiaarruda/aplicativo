import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'service_order.dart';
import 'service_order_details.dart';

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

// Cores do modelo de OS. O PDF é sempre claro: vai para impressão e para
// a caixa de entrada de quem não usa o aplicativo.
const _title = PdfColor.fromInt(0xFF2B4C7E);
const _ink = PdfColor.fromInt(0xFF1F2733);
const _label = PdfColor.fromInt(0xFF6A7890);
const _faint = PdfColor.fromInt(0xFF7C8799);
const _line = PdfColor.fromInt(0xFFDCE3EC);
const _bandColor = PdfColor.fromInt(0xFFE8EFF7);
const _labelCell = PdfColor.fromInt(0xFFF7F9FC);
const _headerCell = PdfColor.fromInt(0xFFEEF3F9);

const _lineWidth = .7;

final _gap = pw.SizedBox(height: 8);

final _dateTime = DateFormat('dd/MM/yyyy HH:mm');
final _date = DateFormat('dd/MM/yyyy');

/// Largura das colunas de rótulo na tabela de dados, como no modelo.
const _labelWidth = 76.0;

Future<Uint8List> buildServiceOrderPdf(
  ServiceOrder order,
  ServiceOrderAssets assets,
) {
  final document = pw.Document(
    title: 'OS ${order.caseNumber}',
    author: order.issuer.responsibleName,
    creator: 'ORION ServiceLog',
    subject: 'Ordem de serviço ${order.caseNumber}',
  );

  document.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(56, 34, 56, 26),
        theme: pw.ThemeData.withFont(base: assets.regular, bold: assets.bold)
            .copyWith(
              defaultTextStyle: pw.TextStyle(
                font: assets.regular,
                fontBold: assets.bold,
                fontSize: 9,
                color: _ink,
                lineSpacing: 1.5,
              ),
            ),
      ),
      // Um atendimento longo de instalação, com semanas de diário e
      // muita medição, passa fácil das 20 páginas do padrão.
      maxPages: 200,
      header: (context) =>
          context.pageNumber == 1 ? pw.SizedBox() : _continuationHeader(order),
      footer: (context) => _footer(order, context),
      // A faixa de título vai sempre junto do primeiro bloco da seção,
      // num bloco só (`_together`): sozinha no pé da página, ela não
      // diria nada.
      build: (context) => [
        _header(order, assets),
        pw.SizedBox(height: 12),
        _together(
          children: [
            _band('Dados do atendimento'),
            _serviceData(order),
            pw.SizedBox(height: 8),
            _times(order),
          ],
        ),
        _gap,
        _band('Relato, diagnóstico e execução'),
        _textRows(order.narrative, minHeight: 30),
        _gap,
        _band('Materiais aplicados'),
        _materials(order.materials),
        _gap,
        _together(
          children: [
            _band('Testes e verificações finais'),
            _checks(order.checks),
          ],
        ),
        if (order.testNotes.isNotEmpty)
          _textRows(order.testNotes, openTop: true),
        _gap,
        ..._closing(order),
        pw.SizedBox(height: 10),
        _signatures(order),
      ],
    ),
  );

  return document.save();
}

pw.Widget _header(ServiceOrder order, ServiceOrderAssets assets) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Image(pw.MemoryImage(assets.logo), height: 30),
      pw.Spacer(),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'ORDEM DE SERVIÇO',
            style: pw.TextStyle(
              fontSize: 12,
              color: _title,
              letterSpacing: 1.6,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Nº ${order.caseNumber}   |   ${_date.format(order.issuedAt)}',
            style: const pw.TextStyle(fontSize: 9, color: _faint),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _continuationHeader(ServiceOrder order) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.only(bottom: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: _line, width: _lineWidth),
      ),
    ),
    child: pw.Row(
      children: [
        pw.Text(
          'ORDEM DE SERVIÇO  Nº ${order.caseNumber}',
          style: pw.TextStyle(
            color: _title,
            fontSize: 8.5,
            letterSpacing: 1.2,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Spacer(),
        pw.Text(
          'continuação',
          style: const pw.TextStyle(color: _faint, fontSize: 8),
        ),
      ],
    ),
  );
}

pw.Widget _footer(ServiceOrder order, pw.Context context) {
  const style = pw.TextStyle(fontSize: 7, color: _faint, lineSpacing: 1);
  final issuer = order.issuer;
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    padding: const pw.EdgeInsets.only(top: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: _line, width: _lineWidth),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (issuer.companyLine.isNotEmpty)
                pw.Text(issuer.companyLine, style: style),
              if (issuer.responsibleLine.isNotEmpty)
                pw.Text(issuer.responsibleLine, style: style),
            ],
          ),
        ),
        if (context.pagesCount > 1)
          pw.Text('${context.pageNumber}/${context.pagesCount}', style: style),
      ],
    ),
  );
}

/// Blocos que não podem ser separados por uma quebra de página.
///
/// Um `Column` solto é dividido pelo MultiPage entre páginas — e um
/// `Container` em volta não impede, porque repassa a divisão ao filho.
pw.Widget _together({required List<pw.Widget> children}) => pw.Inseparable(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: children,
  ),
);

/// Faixa azul-clara com o título da seção.
pw.Widget _band(String title) {
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    color: _bandColor,
    child: pw.Text(
      title.toUpperCase(),
      style: pw.TextStyle(
        color: _title,
        fontSize: 8.5,
        letterSpacing: 1.6,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.TextStyle get _labelStyle => pw.TextStyle(
  fontSize: 7.5,
  color: _label,
  letterSpacing: .8,
  fontWeight: pw.FontWeight.bold,
  lineSpacing: 1,
);

pw.Widget _labelCellOf(String text) => pw.Container(
  color: _labelCell,
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
  child: pw.Text(text.toUpperCase(), style: _labelStyle),
);

pw.Widget _valueCell(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
  child: pw.Text(text),
);

pw.TableBorder _grid({bool top = true}) => pw.TableBorder(
  left: const pw.BorderSide(color: _line, width: _lineWidth),
  right: const pw.BorderSide(color: _line, width: _lineWidth),
  bottom: const pw.BorderSide(color: _line, width: _lineWidth),
  top: top
      ? const pw.BorderSide(color: _line, width: _lineWidth)
      : pw.BorderSide.none,
  horizontalInside: const pw.BorderSide(color: _line, width: _lineWidth),
  verticalInside: const pw.BorderSide(color: _line, width: _lineWidth),
);

/// Cliente e endereço ocupam a linha toda; setor, solicitante,
/// equipamento e série dividem a linha em duas colunas. Tabelas separadas
/// porque a do PDF não junta células.
pw.Widget _serviceData(ServiceOrder order) {
  const wide = {0: pw.FixedColumnWidth(_labelWidth), 1: pw.FlexColumnWidth()};
  const split = {
    0: pw.FixedColumnWidth(_labelWidth),
    1: pw.FlexColumnWidth(),
    2: pw.FixedColumnWidth(_labelWidth),
    3: pw.FlexColumnWidth(),
  };
  return pw.Column(
    children: [
      pw.Table(
        border: _grid(),
        columnWidths: wide,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          pw.TableRow(
            children: [_labelCellOf('Cliente'), _valueCell(order.customer)],
          ),
          pw.TableRow(
            children: [_labelCellOf('Endereço'), _valueCell(order.address)],
          ),
        ],
      ),
      pw.Table(
        border: _grid(top: false),
        columnWidths: split,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          pw.TableRow(
            children: [
              _labelCellOf('Setor'),
              _valueCell(order.sector),
              _labelCellOf('Solicitante'),
              _valueCell(order.requester),
            ],
          ),
          pw.TableRow(
            children: [
              _labelCellOf('Equipamento'),
              _valueCell(order.equipment),
              _labelCellOf('Nº de série / patrimônio'),
              _valueCell(order.serialAndTag),
            ],
          ),
          pw.TableRow(
            children: [
              _labelCellOf('Fabricante / modelo'),
              _valueCell(order.manufacturerModel),
              _labelCellOf(''),
              _valueCell(''),
            ],
          ),
        ],
      ),
    ],
  );
}

pw.Widget _times(ServiceOrder order) {
  String at(DateTime? value) => value == null ? '' : _dateTime.format(value);
  final cells = [
    ('Abertura do chamado', at(order.openedAt)),
    ('Início', at(order.startedAt)),
    ('Término', at(order.finishedAt)),
    (
      'Parada total',
      order.downtimeMinutes == null
          ? ''
          : ServiceOrder.formatMinutes(order.downtimeMinutes!),
    ),
  ];
  return pw.Table(
    border: _grid(),
    defaultColumnWidth: const pw.FlexColumnWidth(),
    children: [
      pw.TableRow(
        children: [
          for (final (label, value) in cells)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(label.toUpperCase(), style: _labelStyle),
                  pw.SizedBox(height: 3),
                  pw.Text(value),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

/// Campos de texto livre, um por linha da tabela, com o rótulo em cima.
///
/// A linha de uma tabela não se divide entre páginas. Um procedimento
/// de várias páginas é quebrado em pedaços antes, e cada pedaço vira uma
/// linha — só a primeira leva o rótulo.
pw.Widget _textRows(
  List<ServiceOrderField> fields, {
  double minHeight = 0,
  bool openTop = false,
  bool separators = true,
  double topPadding = 5,
}) {
  final rows = <pw.TableRow>[];
  for (final field in fields) {
    final pieces = splitForPages(field.value);
    for (var i = 0; i < pieces.length; i++) {
      rows.add(
        pw.TableRow(
          children: [
            pw.Container(
              constraints: pw.BoxConstraints(minHeight: i == 0 ? minHeight : 0),
              padding: pw.EdgeInsets.fromLTRB(6, i == 0 ? topPadding : 0, 6, 6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (i == 0) ...[
                    pw.Text(field.label.toUpperCase(), style: _labelStyle),
                    pw.SizedBox(height: 3),
                  ],
                  if (pieces[i].isNotEmpty) pw.Text(pieces[i]),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
  return pw.Table(
    border: pw.TableBorder(
      left: const pw.BorderSide(color: _line, width: _lineWidth),
      right: const pw.BorderSide(color: _line, width: _lineWidth),
      bottom: const pw.BorderSide(color: _line, width: _lineWidth),
      top: openTop
          ? pw.BorderSide.none
          : const pw.BorderSide(color: _line, width: _lineWidth),
      horizontalInside: separators
          ? const pw.BorderSide(color: _line, width: _lineWidth)
          : pw.BorderSide.none,
    ),
    defaultColumnWidth: const pw.FlexColumnWidth(),
    children: rows,
  );
}

/// Divide um texto longo em pedaços que cabem numa página, cortando de
/// preferência em quebras de linha e, na falta delas, entre palavras.
List<String> splitForPages(String text, {int maxLength = 1400}) {
  final trimmed = text.trim();
  if (trimmed.length <= maxLength) return [trimmed];
  final pieces = <String>[];
  var rest = trimmed;
  while (rest.length > maxLength) {
    var cut = rest.lastIndexOf('\n', maxLength);
    if (cut < maxLength ~/ 2) cut = rest.lastIndexOf(' ', maxLength);
    if (cut <= 0) cut = maxLength;
    pieces.add(rest.substring(0, cut).trimRight());
    rest = rest.substring(cut).trimLeft();
  }
  if (rest.isNotEmpty) pieces.add(rest);
  return pieces;
}

pw.Widget _materials(List<ServiceOrderMaterial> materials) {
  pw.Widget header(String text) => pw.Container(
    color: _headerCell,
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(text.toUpperCase(), style: _labelStyle),
  );
  return pw.Table(
    border: _grid(),
    columnWidths: const {
      0: pw.FlexColumnWidth(3.1),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(.6),
      3: pw.FlexColumnWidth(1.4),
    },
    children: [
      pw.TableRow(
        repeat: true,
        children: [
          header('Descrição'),
          header('Código / PN'),
          header('Qtd.'),
          header('Garantia'),
        ],
      ),
      if (materials.isEmpty)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
              child: pw.Text(
                'Nenhum material aplicado.',
                style: const pw.TextStyle(color: _faint),
              ),
            ),
            pw.SizedBox(),
            pw.SizedBox(),
            pw.SizedBox(),
          ],
        )
      else
        for (final material in materials)
          pw.TableRow(
            children: [
              _valueCell(material.description.trim()),
              _valueCell(material.partNumber.trim()),
              _valueCell(material.quantity.trim()),
              _valueCell(material.warranty.trim()),
            ],
          ),
    ],
  );
}

/// "[ X ]" ou "[    ]", como no modelo impresso.
pw.Widget _box(bool checked, {double fontSize = 9}) {
  return pw.SizedBox(
    width: fontSize * 2.2,
    child: pw.Text(
      checked ? '[X]' : '[   ]',
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: checked ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _checks(Set<ServiceOrderCheck> checks) {
  const perColumn = 3;
  final columns = [
    for (var i = 0; i < ServiceOrderCheck.values.length; i += perColumn)
      ServiceOrderCheck.values.sublist(i, i + perColumn),
  ];
  return pw.Table(
    border: _grid(),
    defaultColumnWidth: const pw.FlexColumnWidth(),
    children: [
      pw.TableRow(
        children: [
          for (final column in columns)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final check in column)
                    pw.Row(
                      children: [
                        _box(checks.contains(check)),
                        pw.Expanded(child: pw.Text(check.label)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

pw.Widget _situation(ServiceOrder order) {
  final selected = order.situation;
  pw.Widget option(ServiceOrderSituation value, {bool primary = false}) {
    final checked = selected == value;
    final size = primary ? 10.0 : 9.0;
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _box(checked, fontSize: size),
        pw.Text(
          value.label,
          style: pw.TextStyle(
            fontSize: size,
            color: checked || primary ? _ink : _faint,
            fontWeight: checked || primary
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // Sem borda embaixo: as recomendações continuam a mesma caixa, numa
  // tabela à parte que pode seguir para a página seguinte.
  return pw.Table(
    border: const pw.TableBorder(
      left: pw.BorderSide(color: _line, width: _lineWidth),
      right: pw.BorderSide(color: _line, width: _lineWidth),
      top: pw.BorderSide(color: _line, width: _lineWidth),
    ),
    defaultColumnWidth: const pw.FlexColumnWidth(),
    children: [
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                option(ServiceOrderSituation.released, primary: true),
                pw.SizedBox(height: 2),
                pw.Wrap(
                  spacing: 18,
                  children: [
                    option(ServiceOrderSituation.restricted),
                    option(ServiceOrderSituation.inoperative),
                    option(ServiceOrderSituation.awaiting),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

/// Situação final e recomendações. Com recomendações curtas — o caso
/// comum —, a seção inteira fica numa coluna só e muda de página junta;
/// só uma recomendação de mais de uma página é deixada quebrar.
List<pw.Widget> _closing(ServiceOrder order) {
  final recommendations = _textRows(
    [ServiceOrderField('Recomendações', order.recommendations)],
    openTop: true,
    separators: false,
    topPadding: 0,
  );
  final head = [_band('Situação final e pendências'), _situation(order)];
  if (splitForPages(order.recommendations).length > 1) {
    return [_together(children: head), recommendations];
  }
  return [
    _together(children: [...head, recommendations]),
  ];
}

/// Local, data e as duas assinaturas, sempre juntos na mesma página.
pw.Widget _signatures(ServiceOrder order) {
  pw.Widget signature(String name, String caption) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _faint, width: .6)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            name,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (caption.isNotEmpty)
            pw.Text(
              caption,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8, color: _label),
            ),
        ],
      ),
    ),
  );

  final issuer = order.issuer;
  return _together(
    children: [
      pw.Text(order.placeAndDate),
      pw.SizedBox(height: 28),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          signature(
            issuer.responsibleName.isEmpty
                ? 'Responsável técnico'
                : issuer.responsibleName,
            issuer.responsibleName.isEmpty ? '' : issuer.signatureCaption,
          ),
          pw.SizedBox(width: 28),
          signature('Cliente — recebimento e aceite', ''),
        ],
      ),
    ],
  );
}
