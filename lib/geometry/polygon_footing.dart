// lib/geometry/polygon_footing.dart
// Pure geometry helpers for polygons (no Flutter widgets).

import 'dart:ui' as ui;

class PolygonFooting {
  /// Robust parser for coordinates.
  ///
  /// Accepts any of these formats (mixed is fine):
  ///   - "0 0, 2 0, 2 1, 0 1"
  ///   - "0,0; 2,0; 2,1; 0,1"
  ///   - "0 0\n2 0\n2 1\n0 1"
  ///   - extra spaces/commas/semicolons/newlines tolerated
  ///
  /// Numbers may be negative and/or use decimals. We read tokens in pairs.
  static List<ui.Offset> parsePoints(String s) {
    if (s.trim().isEmpty) return const [];

    // Normalize delimiters to spaces.
    final normalized = s.replaceAll(RegExp(r'[,\n;\t]+'), ' ').trim();

    // Split to scalar tokens, then read as (x,y) pairs.
    final parts = normalized.split(RegExp(r'\s+'));
    final pts = <ui.Offset>[];
    for (int i = 0; i + 1 < parts.length; i += 2) {
      final x = double.tryParse(parts[i]);
      final y = double.tryParse(parts[i + 1]);
      if (x != null && y != null) {
        // Skip duplicate consecutive vertices (nice to have).
        if (pts.isEmpty || pts.last.dx != x || pts.last.dy != y) {
          pts.add(ui.Offset(x, y));
        }
      }
    }
    return pts;
  }

  /// Polygon area via shoelace (always positive).
  static double area(List<ui.Offset> pts) {
    if (pts.length < 3) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];
      final q = pts[(i + 1) % pts.length];
      sum += p.dx * q.dy - q.dx * p.dy;
    }
    return sum.abs() * 0.5;
  }

  /// Path centered at centroid (so its centroid is near (0,0)).
  static ui.Path pathCentered(List<ui.Offset> pts) {
    final path = ui.Path();
    if (pts.length < 3) return path;

    final a = area(pts);
    if (a == 0) {
      // Degenerate; just draw as-is (could be a line).
      path.addPolygon(pts, true);
      return path;
    }

    // Centroid from shoelace terms.
    double cx = 0.0, cy = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];
      final q = pts[(i + 1) % pts.length];
      final cross = p.dx * q.dy - q.dx * p.dy;
      cx += (p.dx + q.dx) * cross;
      cy += (p.dy + q.dy) * cross;
    }
    cx /= (6 * a);
    cy /= (6 * a);

    final shifted = pts.map((p) => ui.Offset(p.dx - cx, p.dy - cy)).toList();
    path.addPolygon(shifted, true);
    return path;
  }
}
