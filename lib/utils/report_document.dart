import 'dart:typed_data';

import 'docx_writer.dart';
import 'xlsx_writer.dart';

/// One table of a report: a heading, column titles and rows.
///
/// Cells may be text or numbers. In Excel a number stays a number (so it can be
/// sorted and charted); in Word everything is printed as text.
class ReportSection {
  const ReportSection({
    required this.heading,
    required this.headers,
    required this.rows,
    this.note,
    this.columnWeights,
    this.excelWidths,
    this.wordColumns,
    this.wordFontSize,
  });

  final String heading;
  final List<String> headers;
  final List<List<Object?>> rows;

  /// A line under the table (a caveat, a definition).
  final String? note;

  /// Relative column widths in the Word table (one per Word column).
  final List<int>? columnWeights;

  /// Column widths, in characters, on this section's Excel sheet.
  final List<double>? excelWidths;

  /// Which columns (by index) go into the Word table. A long list has more
  /// columns than a page can show; Excel keeps them all, Word shows the ones a
  /// reader needs. Null = every column.
  final List<int>? wordColumns;

  /// Word table text size in half-points (18 = 9 pt).
  final int? wordFontSize;
}

/// A report that can be handed over as an Excel workbook OR a Word document —
/// the same figures either way, never a different set per format.
///
/// There is deliberately no PDF here: officials asked to be able to open and edit
/// what they export (Excel to work with the numbers, Word to put them in a
/// document), which a PDF does not allow.
class ReportDocument {
  const ReportDocument({
    required this.title,
    required this.infoLines,
    required this.sections,
    this.footer,
    this.landscape = false,
  });

  final String title;

  /// Word only: lay the pages on their side, for wide tables.
  final bool landscape;

  /// Who / where / when / which period — printed under the title.
  final List<String> infoLines;
  final List<ReportSection> sections;
  final String? footer;

  /// Excel: an "About" sheet (title and the info lines), then one sheet per
  /// section, so each table can be sorted and charted on its own.
  Uint8List toXlsx() {
    return writeXlsx([
      XlsxSheet(
        'About',
        [
          [XlsxCell(title, bold: true)],
          for (final l in infoLines) [l],
          if (footer != null) ...[[], [footer]],
        ],
        columnWidths: const [80],
      ),
      for (final s in sections)
        XlsxSheet(
          s.heading,
          [
            [for (final h in s.headers) XlsxCell(h, header: true)],
            ...s.rows,
            if (s.note != null) ...[[], [s.note]],
          ],
          columnWidths: s.excelWidths ?? [30, for (var i = 1; i < s.headers.length; i++) 18],
          freezeHeaderRow: true,
        ),
    ]);
  }

  /// Word: the title, the info lines, then each section as a heading and a table.
  Uint8List toDocx() {
    return writeDocx([
      DocxParagraph(title, style: DocxStyle.title),
      for (final l in infoLines) DocxParagraph(l, style: DocxStyle.small),
      for (final s in sections) ...[
        DocxParagraph(s.heading, style: DocxStyle.heading1),
        _wordTable(s),
        if (s.note != null) DocxParagraph(s.note!, style: DocxStyle.small),
      ],
      if (footer != null) ...[
        const DocxParagraph(''),
        DocxParagraph(footer!, style: DocxStyle.small),
      ],
    ], landscape: landscape);
  }

  static DocxTable _wordTable(ReportSection s) {
    final keep = s.wordColumns ?? [for (var i = 0; i < s.headers.length; i++) i];
    return DocxTable(
      [for (final i in keep) s.headers[i]],
      [
        for (final row in s.rows)
          [
            for (final i in keep)
              i < row.length && row[i] != null ? _plain(row[i]!) : '',
          ],
      ],
      columnWeights: s.columnWeights,
      fontSize: s.wordFontSize,
    );
  }

  static String _plain(Object c) {
    if (c is double) return c == c.roundToDouble() ? c.toInt().toString() : c.toString();
    return c.toString();
  }
}
