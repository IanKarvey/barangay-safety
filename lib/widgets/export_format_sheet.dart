import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// A file type an official can export to. PDF is deliberately not on the list:
/// these are files to open, edit and reuse.
enum ExportFormat {
  excel('xlsx', 'Excel', '.xlsx', 'Rows and columns you can sort, filter and chart.',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  word('docx', 'Word', '.docx', 'A document you can edit and put into your own report.',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document');

  const ExportFormat(this.extension, this.label, this.suffix, this.blurb, this.mimeType);

  final String extension;
  final String label;
  final String suffix;
  final String blurb;
  final String mimeType;
}

/// Asks which format to export to. Returns null if the person backs out.
Future<ExportFormat?> showExportFormatSheet(BuildContext context) {
  return showModalBottomSheet<ExportFormat>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export report as', style: AppTextStyles.heading3),
            const SizedBox(height: 12),
            for (final f in ExportFormat.values) ...[
              _FormatTile(format: f, onTap: () => Navigator.of(ctx).pop(f)),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    ),
  );
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.format, required this.onTap});

  final ExportFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final excel = format == ExportFormat.excel;
    final color = excel ? const Color(0xFF16A34A) : const Color(0xFF2563EB);
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(
                    excel ? 'X' : 'W',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${format.label} (${format.suffix})',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(format.blurb, style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
