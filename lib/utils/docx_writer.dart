import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One piece of a Word document.
sealed class DocxBlock {
  const DocxBlock();
}

enum DocxStyle { title, heading1, heading2, normal, small }

/// A paragraph. [bold] and [color] (hex, no #) apply to the whole paragraph.
class DocxParagraph extends DocxBlock {
  const DocxParagraph(this.text, {this.style = DocxStyle.normal, this.bold = false, this.color});

  final String text;
  final DocxStyle style;
  final bool bold;
  final String? color;
}

/// A table with a shaded header row that repeats on every page.
class DocxTable extends DocxBlock {
  const DocxTable(this.headers, this.rows, {this.columnWeights, this.fontSize});

  final List<String> headers;
  final List<List<String>> rows;

  /// Text size in half-points (18 = 9 pt). Smaller type lets a wide table such as
  /// the report list fit on the page; null keeps the document's normal size.
  final int? fontSize;

  /// Relative widths, e.g. `[3, 1]` for a wide first column. Equal when null.
  final List<int>? columnWeights;
}

/// Writes a minimal but valid Word (.docx) document.
///
/// A .docx is a zip of small XML parts, so — like the Excel export — this needs
/// only the `zip` encoder already in the app. Scope is what a printed report
/// needs: a title, headings, paragraphs and tables, on A4 with sensible margins.
Uint8List writeDocx(List<DocxBlock> blocks, {bool landscape = false}) {
  final archive = Archive();
  void add(String path, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _rootRels);
  add('word/_rels/document.xml.rels', _documentRels);
  add('word/styles.xml', _styles);
  add('word/document.xml', _document(blocks, landscape));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

const _contentTypes = '$_xmlHead'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const _rootRels = '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

const _documentRels = '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

const _styles = '$_xmlHead'
    '<w:styles $_ns>'
    '<w:docDefaults>'
    '<w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
    '</w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:spacing w:after="60"/></w:pPr><w:rPr><w:b/><w:color w:val="1D4ED8"/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="320" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="0F172A"/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="200" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:color w:val="334155"/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Small"><w:name w:val="Small"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="64748B"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
    '<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/>'
    '<w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>'
    '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/>'
    '<w:tblPr><w:tblBorders>'
    '<w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/><w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/><w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
    '</w:tblBorders><w:tblCellMar><w:top w:w="60" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="60" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>'
    '</w:styles>';

// A4 with 2 cm margins: 11906 x 16838 twips. Text width is the page width less
// both margins: 9638 upright, 14570 on its side.
const _portraitWidth = 9638;
const _landscapeWidth = 14570;

String _document(List<DocxBlock> blocks, bool landscape) {
  final textWidth = landscape ? _landscapeWidth : _portraitWidth;
  final b = StringBuffer(_xmlHead)..write('<w:document $_ns><w:body>');
  for (final block in blocks) {
    switch (block) {
      case DocxParagraph():
        b.write(_paragraph(block));
      case DocxTable():
        b.write(_table(block, textWidth));
        // Word insists on a paragraph after a table, and without one a second
        // table would be glued to the first.
        b.write('<w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>');
    }
  }
  final pgSz = landscape
      ? '<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'
      : '<w:pgSz w:w="11906" w:h="16838"/>';
  b.write('<w:sectPr>$pgSz'
      '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>');
  return b.toString();
}

String _styleId(DocxStyle s) => switch (s) {
      DocxStyle.title => 'Title',
      DocxStyle.heading1 => 'Heading1',
      DocxStyle.heading2 => 'Heading2',
      DocxStyle.small => 'Small',
      DocxStyle.normal => 'Normal',
    };

String _run(String text, {bool bold = false, String? color, int? size}) {
  final props = StringBuffer();
  if (bold) props.write('<w:b/>');
  if (color != null) props.write('<w:color w:val="$color"/>');
  if (size != null) props.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/>');
  final rPr = props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
  return '<w:r>$rPr<w:t xml:space="preserve">${_text(text)}</w:t></w:r>';
}

String _paragraph(DocxParagraph p) =>
    '<w:p><w:pPr><w:pStyle w:val="${_styleId(p.style)}"/></w:pPr>${_run(p.text, bold: p.bold, color: p.color)}</w:p>';

String _table(DocxTable t, int textWidth) {
  final cols = t.headers.length;
  final weights = (t.columnWeights != null && t.columnWeights!.length == cols)
      ? t.columnWeights!
      : List.filled(cols, 1);
  final total = weights.fold<int>(0, (a, b) => a + b);
  final widths = [for (final w in weights) (textWidth * w / total).floor()];

  String cell(String text, int width, {bool header = false}) {
    final shade = header ? '<w:shd w:val="clear" w:color="auto" w:fill="1D4ED8"/>' : '';
    final run = _run(text, bold: header, color: header ? 'FFFFFF' : null, size: t.fontSize);
    return '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>$shade</w:tcPr>'
        '<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>$run</w:p></w:tc>';
  }

  final b = StringBuffer()
    ..write('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="$textWidth" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
        '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr>')
    ..write('<w:tblGrid>');
  for (final w in widths) {
    b.write('<w:gridCol w:w="$w"/>');
  }
  b.write('</w:tblGrid>');

  b.write('<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>');
  for (var i = 0; i < cols; i++) {
    b.write(cell(t.headers[i], widths[i], header: true));
  }
  b.write('</w:tr>');

  for (final row in t.rows) {
    b.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>');
    for (var i = 0; i < cols; i++) {
      b.write(cell(i < row.length ? row[i] : '', widths[i]));
    }
    b.write('</w:tr>');
  }
  b.write('</w:tbl>');
  return b.toString();
}

/// XML text: escape the markup characters and drop control characters XML 1.0
/// forbids outright (one stray byte would make Word refuse to open the file).
String _text(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]'), '');
  return cleaned
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
