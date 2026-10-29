import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A cell with a style. A bare `String`, `num` or `null` in a row is a plain
/// cell; wrap it in an [XlsxCell] to make it bold or a column header.
class XlsxCell {
  const XlsxCell(this.value, {this.bold = false, this.header = false});

  final Object? value;
  final bool bold;

  /// Bold on a grey fill, text wrapped — the look of a table's first row.
  final bool header;
}

class XlsxSheet {
  const XlsxSheet(
    this.name,
    this.rows, {
    this.columnWidths = const [],
    this.freezeHeaderRow = false,
  });

  final String name;

  /// Each row is a list of `String`, `num`, `bool`, `null` or [XlsxCell].
  final List<List<Object?>> rows;

  /// Width in characters, per column; missing columns get the default.
  final List<double> columnWidths;

  /// Keep row 1 on screen while scrolling a long table.
  final bool freezeHeaderRow;
}

/// Writes a minimal but valid Excel (.xlsx) workbook.
///
/// An .xlsx file is a zip of small XML documents, so this needs only the `zip`
/// encoder that is already in the app — no spreadsheet library, and with it none
/// of the version changes a library would drag into the photo and PDF code that
/// shares the same dependencies.
///
/// Scope is deliberately small: text, numbers, a bold/grey header style, column
/// widths and a frozen header row. Text is stored inline rather than in a shared
/// string table, which Excel, LibreOffice and Google Sheets all read.
Uint8List writeXlsx(List<XlsxSheet> sheets) {
  assert(sheets.isNotEmpty, 'a workbook needs at least one sheet');
  final names = _uniqueSheetNames(sheets.map((s) => s.name).toList());

  final archive = Archive();
  void add(String path, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes(sheets.length));
  add('_rels/.rels', _rootRels);
  add('xl/workbook.xml', _workbook(names));
  add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
  add('xl/styles.xml', _styles);
  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _worksheet(sheets[i]));
  }

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

// ── Parts ───────────────────────────────────────────────────────────────────

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

String _contentTypes(int sheetCount) {
  final b = StringBuffer(_xmlHead)
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  for (var i = 1; i <= sheetCount; i++) {
    b.write('<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  b.write('</Types>');
  return b.toString();
}

const _rootRels = '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<String> names) {
  final b = StringBuffer(_xmlHead)
    ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    ..write('<sheets>');
  for (var i = 0; i < names.length; i++) {
    b.write('<sheet name="${_attr(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  b.write('</sheets></workbook>');
  return b.toString();
}

String _workbookRels(int sheetCount) {
  final b = StringBuffer(_xmlHead)
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (var i = 1; i <= sheetCount; i++) {
    b.write('<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>');
  }
  b.write('<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  b.write('</Relationships>');
  return b.toString();
}

// Style indexes used below: 0 normal, 1 bold, 2 header (bold, grey fill, wrap).
const _styles = '$_xmlHead'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="3">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE2E8F0"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="3">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1">'
    '<alignment vertical="top" wrapText="1"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

String _worksheet(XlsxSheet sheet) {
  final b = StringBuffer(_xmlHead)
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');

  if (sheet.freezeHeaderRow) {
    b.write('<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>');
  }

  if (sheet.columnWidths.isNotEmpty) {
    b.write('<cols>');
    for (var i = 0; i < sheet.columnWidths.length; i++) {
      b.write('<col min="${i + 1}" max="${i + 1}" width="${sheet.columnWidths[i]}" customWidth="1"/>');
    }
    b.write('</cols>');
  }

  b.write('<sheetData>');
  for (var r = 0; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    b.write('<row r="${r + 1}">');
    for (var c = 0; c < row.length; c++) {
      b.write(_cell(r, c, row[c]));
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

String _cell(int r, int c, Object? raw) {
  final style = raw is XlsxCell ? (raw.header ? 2 : (raw.bold ? 1 : 0)) : 0;
  final value = raw is XlsxCell ? raw.value : raw;
  final ref = '${_columnName(c)}${r + 1}';
  final s = style == 0 ? '' : ' s="$style"';

  if (value == null) return style == 0 ? '' : '<c r="$ref"$s/>';
  if (value is num && value.isFinite) return '<c r="$ref"$s><v>$value</v></c>';
  final text = value is bool ? (value ? 'Yes' : 'No') : value.toString();
  if (text.isEmpty) return style == 0 ? '' : '<c r="$ref"$s/>';
  return '<c r="$ref"$s t="inlineStr"><is><t xml:space="preserve">${_text(text)}</t></is></c>';
}

/// 0 -> A, 25 -> Z, 26 -> AA.
String _columnName(int index) {
  var n = index;
  final out = StringBuffer();
  do {
    out.write(String.fromCharCode(65 + n % 26));
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return out.toString().split('').reversed.join();
}

/// XML text: escape the markup characters and drop control characters that XML
/// 1.0 forbids outright (one stray byte would make Excel refuse the whole file).
String _text(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]'), '');
  return cleaned
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _attr(String s) => _text(s).replaceAll('"', '&quot;');

/// Sheet names: at most 31 characters, none of `[]:*?/\`, and no two the same
/// (Excel treats names case-insensitively).
List<String> _uniqueSheetNames(List<String> wanted) {
  final used = <String>{};
  final out = <String>[];
  for (final raw in wanted) {
    var base = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (base.isEmpty) base = 'Sheet';
    if (base.length > 31) base = base.substring(0, 31);
    var name = base;
    var n = 2;
    while (!used.add(name.toLowerCase())) {
      final suffix = ' ($n)';
      name = base.substring(0, base.length.clamp(0, 31 - suffix.length)) + suffix;
      n++;
    }
    out.add(name);
  }
  return out;
}
