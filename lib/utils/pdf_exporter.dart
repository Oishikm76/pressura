// lib/utils/pdf_exporter.dart
// Lightweight PDF export for Pressura results.
// Requires: pdf, path_provider

import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfExporter {
  /// Builds and saves a PDF report.
  ///
  /// [chartPng] is an optional PNG (e.g., from a RepaintBoundary) to embed.
  /// [meshesPerRing] (optional) is the per-ring count of sectors under the footing;
  /// it is rendered as the N count per ring.
  /// [ringSigmaRatios] (optional) holds the sigma_z/q value for each ring (same length as meshesPerRing).
  static Future<File> saveReport({
    required String fileBaseName,
    required String title,
    required Map<String, String> infoRows,
    Uint8List? chartPng,
    String? notes,

    // Per-ring coverage details (N per ring)
    List<int>? meshesPerRing,
    List<double>? ringSigmaRatios,
  }) async {
    final doc = pw.Document();

    // Built-in monospace font.
    final courier = pw.Font.courier();

    // Replace Greek symbols with ASCII words for the whole PDF.
    String _asciiize(String s) {
      return s
          .replaceAll('σ', 'sigma')
          .replaceAll('Σ', 'Sigma')
          .replaceAll('Δ', 'Delta')
          .replaceAll('δ', 'delta');
    }

    // Render key/value rows with ascii-ized text.
    pw.Widget buildInfoTable() {
      final rows = infoRows.entries
          .map(
            (e) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    _asciiize(e.key),
                    style: pw.TextStyle(font: courier),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  _asciiize(e.value),
                  style: pw.TextStyle(font: courier),
                ),
              ],
            ),
          )
          .toList();
      return pw.Column(children: rows);
    }

    // Table: N count per ring.
    pw.Widget? buildNPerRingTable() {
      if (meshesPerRing == null || meshesPerRing.isEmpty) return null;

      final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold);
      final monospace = pw.TextStyle(font: courier);

      final rows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Ring #', style: headerStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('sigma_z/q at ring', style: headerStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('N_i (sectors covered)', style: headerStyle),
            ),
          ],
        ),
      ];

      for (int i = 0; i < meshesPerRing.length; i++) {
        final ringIdx = i + 1;
        final n_i = meshesPerRing[i];
        final ratio = (ringSigmaRatios != null && i < ringSigmaRatios.length)
            ? ringSigmaRatios[i].toStringAsFixed(4)
            : '—';
        rows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('$ringIdx', style: monospace),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(ratio, style: monospace),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('$n_i', style: monospace),
              ),
            ],
          ),
        );
      }

      final totalN = meshesPerRing.fold<int>(0, (a, b) => a + b);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'N count per ring',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.8),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: rows,
          ),
          pw.SizedBox(height: 6),
          pw.Text('Total N (sum of rings): $totalN', style: monospace),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              _asciiize(title),
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Newmark Influence Chart — Pressura',
            style: const pw.TextStyle(
              color: PdfColors.grey,
              fontSize: 12,
            ),
          ),
          pw.SizedBox(height: 16),

          // Info table
          buildInfoTable(),
          pw.SizedBox(height: 14),

          // Formula block (ASCII only)
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              'Formula:  sigma_z = If × N × q\n'
              'Where: If = Delta(sigma_z/q) / Nr',
              style: pw.TextStyle(font: courier),
            ),
          ),

          if (notes != null) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              _asciiize(notes),
              style: pw.TextStyle(font: courier, fontSize: 11),
            ),
          ],

          // N per ring table (if provided)
          if (buildNPerRingTable() != null) ...[
            pw.SizedBox(height: 16),
            buildNPerRingTable()!,
          ],

          if (chartPng != null) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Chart snapshot',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Image(pw.MemoryImage(chartPng), width: 420),
            ),
          ],
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileBaseName.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }
}
