// Pressura — Newmark Influence Chart Stress Calculator
// main.dart — complete app with Polygon footing + PDF export
//
// Features:
// • Choose footing shape (circular / square / rectangular / polygon) and dimensions (m)
// • Enter P (kN) to compute q = P/A (kPa) or input q directly (kPa)
// • Enter depth z (m), Δ(σz/q), (σz/q)_max, and nr radial lines
// • Interactive chart: pinch (scale), rotate, drag footing; HUD shows live N and σz
// • Formula: σz = If × N × q, with If = Δ(σz/q) / nr
// • Export PDF with chart snapshot + inputs summary
//
// Notes:
// • N is approximated by counting sector centers under the footing (classic Newmark method)
// • No third-party drawing libs; CustomPainter only
// • Flutter 3.x (Material 3, Color.withValues API)
import 'geometry/polygon_footing.dart';

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';


import 'utils/pdf_exporter.dart';

void main() => runApp(const PressuraApp());

class PressuraApp extends StatelessWidget {
  const PressuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2D6A4F); // deep green-teal
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Pressura',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        cardTheme: CardThemeData(
          elevation: 1,
          margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
),

        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: const PressuraHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum FootingShape { circular, square, rectangular, polygon }

class PressuraHome extends StatefulWidget {
  const PressuraHome({super.key});

  @override
  State<PressuraHome> createState() => _PressuraHomeState();
}

class _PressuraHomeState extends State<PressuraHome> {
  // Inputs
  FootingShape shape = FootingShape.rectangular;

  // Rect / Square / Circle geometry (meters)
  double L = 2.0; // rectangular length
  double B = 1.2; // rectangular width
  double D = 1.5; // circular diameter
  double a = 1.2; // square side

  // Polygon geometry string (meters)
  String polygonPoints = '0 0, 2 0, 2 1, 0 1';
  List<Offset> get _polyPts => PolygonFooting.parsePoints(polygonPoints);

  // Pressure path
  bool useP = true; // compute q from P/A
  double pTotalKn = 800; // kN
  double qkPa = 100; // kPa (if useP == false)

  // Chart parameters
  double z = 2.0; // m
  double deltaSOverQ = 0.1; // Δ(σz/q)
  double sMax = 0.9; // (σz/q)_max
  int nr = 20; // radial lines

  // Interactive pose (footing in chart coordinates, meters)
  double scale = 1.0; // uniform footing scale
  double rotDeg = 0.0; // rotation of footing
  Offset shift = Offset.zero; // translation (m)

  // HUD computed
  double lastN = 0.0;
  double lastSigma = 0.0; // kPa

  // For export: capture chart PNG
  final GlobalKey _chartKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final area = _footingArea();
    final q = useP ? (area > 0 ? pTotalKn / area : 0.0) : qkPa; // kPa
    final influenceFactor = (nr > 0) ? (deltaSOverQ / nr) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pressura - Newmark Influence Chart Stress Calculator'),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () async {
              await _exportPdf(context, q, influenceFactor);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Intro / method card
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How Pressura calculates stress',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Pressura estimates the vertical stress at depth z (σz) using Newmark\'s influence chart. '
                      'Rings are spaced by Δ(σz/q). The footing is dragged/rotated/scaled over the chart. '
                      'We count how many chart sectors (N) fall under the footing to get: '
                      'σz = If × N × q, where If = Δ(σz/q) / Nr and q is the uniform pressure from P/A or user input.',
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left: controls
                  Flexible(
                    flex: 2,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          _shapeCard(),
                          _loadCard(area),
                          _chartParamsCard(),
                          _poseCard(),
                          _resultCard(q, influenceFactor),
                        ],
                      ),
                    ),
                  ),

                  // Right: chart
                  Flexible(
                    flex: 3,
                    child: Card(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return RepaintBoundary(
                            key: _chartKey,
                            child: _InteractiveChart(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              z: z,
                              deltaSOverQ: deltaSOverQ,
                              sMax: sMax,
                              nr: nr,
                              shape: shape,
                              L: L,
                              B: B,
                              D: D,
                              a: a,
                              polygonPoints: _polyPts,
                              scale: scale,
                              rotDeg: rotDeg,
                              shift: shift,
                              onPoseChanged: (newScale, newRotDeg, newShift, N, sigma) {
                                setState(() {
                                  scale = newScale;
                                  rotDeg = newRotDeg;
                                  shift = newShift;
                                  lastN = N;
                                  lastSigma = sigma;
                                });
                              },
                              qkPa: q,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === UI cards ===

  Widget _shapeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Footing', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<FootingShape>(
              segments: const [
                ButtonSegment(value: FootingShape.circular, label: Text('Circular')),
                ButtonSegment(value: FootingShape.square, label: Text('Square')),
                ButtonSegment(value: FootingShape.rectangular, label: Text('Rectangular')),
                ButtonSegment(value: FootingShape.polygon, label: Text('Polygon')),
              ],
              selected: {shape},
              onSelectionChanged: (sel) => setState(() => shape = sel.first),
            ),
            const SizedBox(height: 8),
            if (shape == FootingShape.circular) ...[
              _numField('Diameter D (m)', D, (v) => setState(() => D = v), min: 0.01),
            ] else if (shape == FootingShape.square) ...[
              _numField('Side a (m)', a, (v) => setState(() => a = v), min: 0.01),
            ] else if (shape == FootingShape.rectangular) ...[
              _numField('Length L (m)', L, (v) => setState(() => L = v), min: 0.01),
              const SizedBox(height: 6),
              _numField('Width B (m)', B, (v) => setState(() => B = v), min: 0.01),
            ] else ...[
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Polygon points (m): x y, x y, ...',
                  helperText: 'Example: 0 0, 2 0, 2 1, 0 1',
                ),
                controller: TextEditingController(text: polygonPoints),
                onSubmitted: (s) => setState(() => polygonPoints = s),
              ),
              const SizedBox(height: 6),
              _infoRow('Footing area A (m²)', PolygonFooting.area(_polyPts).toStringAsFixed(4)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loadCard(double area) {
    final qFromP = area > 0 ? pTotalKn / area : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Loading / Pressure', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Compute q from total load P (kN)?'),
              value: useP,
              onChanged: (v) => setState(() => useP = v),
            ),
            if (useP) ...[
              _numField('Total load P (kN)', pTotalKn, (v) => setState(() => pTotalKn = v), min: 0),
              const SizedBox(height: 6),
              _infoRow('Footing area A (m²)', area.toStringAsFixed(4)),
              _infoRow('Derived q = P/A (kPa)', qFromP.isFinite ? qFromP.toStringAsFixed(3) : '—'),
            ] else ...[
              _numField('Uniform pressure q (kPa)', qkPa, (v) => setState(() => qkPa = v), min: 0),
              const SizedBox(height: 6),
              _infoRow('Footing area A (m²)', area.toStringAsFixed(4)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chartParamsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chart & Depth', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _numField('Depth z (m)', z, (v) => setState(() => z = v), min: 0.01),
            const SizedBox(height: 6),
            _numField('Δ(σz/q) per ring', deltaSOverQ, (v) => setState(() => deltaSOverQ = v), min: 0.001, max: 0.99),
            const SizedBox(height: 6),
            _numField('(σz/q)_max', sMax, (v) => setState(() => sMax = v), min: 0.01, max: 0.999),
            const SizedBox(height: 6),
            _intField('Nr (radial lines)', nr, (v) => setState(() => nr = v), min: 4, max: 360),
          ],
        ),
      ),
    );
  }

  Widget _poseCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Footing Pose', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _infoRow('Scale', scale.toStringAsFixed(3)),
            _infoRow('Rotation (°)', rotDeg.toStringAsFixed(1)),
            _infoRow('Shift (m)', '(${shift.dx.toStringAsFixed(3)}, ${shift.dy.toStringAsFixed(3)})'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() { scale *= 1.02; }),
                  icon: const Icon(Icons.zoom_in),
                  label: const Text('Scale +'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() { scale /= 1.02; }),
                  icon: const Icon(Icons.zoom_out),
                  label: const Text('Scale -'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() { rotDeg += 2; }),
                  icon: const Icon(Icons.rotate_right),
                  label: const Text('Rotate +'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() { rotDeg -= 2; }),
                  icon: const Icon(Icons.rotate_left),
                  label: const Text('Rotate -'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() { shift = Offset.zero; rotDeg = 0; scale = 1; }),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset pose'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(double q, double influenceFactor) {
    final sigma = lastSigma;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live Result', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _infoRow('If = Δ/Nr', '${deltaSOverQ.toStringAsFixed(4)} / $nr = ${influenceFactor.toStringAsFixed(5)}'),
            _infoRow('N (sector count)', lastN.toStringAsFixed(3)),
            _infoRow('q (kPa)', q.isFinite ? q.toStringAsFixed(3) : '—'),
            const Divider(),
            Text(
              'σz = If × N × q = ${influenceFactor.toStringAsFixed(5)} × ${lastN.toStringAsFixed(3)} × ${q.toStringAsFixed(3)} kPa',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            Text(
              'σz ≈ ${sigma.isFinite ? sigma.toStringAsFixed(3) : '—'} kPa',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text('Tip: Smaller Δ and larger Nr increase accuracy (smaller If).'),
          ],
        ),
      ),
    );
  }

  // === helpers ===

  double _footingArea() {
    switch (shape) {
      case FootingShape.circular:
        final r = D / 2;
        return math.pi * r * r;
      case FootingShape.square:
        return a * a;
      case FootingShape.rectangular:
        return L * B;
      case FootingShape.polygon:
        return PolygonFooting.area(_polyPts);
    }
  }

  Widget _numField(
    String label,
    double value,
    void Function(double) onChanged, {
    double? min,
    double? max,
  }) {
    final controller = TextEditingController(text: value.toString());
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
      onSubmitted: (s) {
        final v = double.tryParse(s);
        if (v != null && (min == null || v >= min) && (max == null || v <= max)) {
          onChanged(v);
        }
      },
    );
  }

  Widget _intField(
    String label,
    int value,
    void Function(int) onChanged, {
    int? min,
    int? max,
  }) {
    final controller = TextEditingController(text: value.toString());
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      onSubmitted: (s) {
        final v = int.tryParse(s);
        if (v != null && (min == null || v >= min) && (max == null || v <= max)) {
          onChanged(v);
        }
      },
    );
  }

  Widget _infoRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(k), Text(v, style: const TextStyle(fontFamily: 'monospace'))],
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context, double q, double influenceFactor) async {
    try {
      final png = await _captureChartPng();
      final info = <String, String>{
        'Shape': shape.name,
        if (shape == FootingShape.rectangular) ...{
          'L (m)': L.toStringAsFixed(3),
          'B (m)': B.toStringAsFixed(3),
        },
        if (shape == FootingShape.square) ...{
          'a (m)': a.toStringAsFixed(3),
        },
        if (shape == FootingShape.circular) ...{
          'D (m)': D.toStringAsFixed(3),
        },
        if (shape == FootingShape.polygon) ...{
          'polygon pts': polygonPoints,
        },
        'Area A (m²)': _footingArea().toStringAsFixed(4),
        'Use P?': useP ? 'Yes' : 'No',
        if (useP) 'P (kN)': pTotalKn.toStringAsFixed(3) else 'q (kPa)': qkPa.toStringAsFixed(3),
        'Depth z (m)': z.toStringAsFixed(3),
        'Δ(σz/q)': deltaSOverQ.toStringAsFixed(4),
        '(σz/q)_max': sMax.toStringAsFixed(3),
        'Nr': '$nr',
        'If (Δ/Nr)': influenceFactor.toStringAsFixed(6),
        'N (count)': lastN.toStringAsFixed(3),
        'q (kPa)': q.toStringAsFixed(3),
        'σz (kPa)': lastSigma.toStringAsFixed(3),
      };

      // Compute ring sigma_z/q ratios for export
      final List<double> ringS = [];
      final nRings = math.max((sMax / deltaSOverQ + 1e-12).floor(), 1);
      for (int i = 1; i <= nRings; i++) {
        final s = i * deltaSOverQ;
        if (s > 0 && s < 1) ringS.add(s);
      }

      // Compute meshesPerRing (number of sectors per ring)
      final List<int> nPerRing = List.generate(nRings, (_) => nr);

      // Compute ringSigmaRatios (the sigma_z/q ratios for each ring)
      final List<double> ringRatios = List.generate(nRings, (i) => (i + 1) * deltaSOverQ);

      final file = await PdfExporter.saveReport(
        fileBaseName: 'pressura_report',
        title: 'Pressura - Newmark Influence Chart Report',
        infoRows: info,
        chartPng: png,
        notes: '...',
        meshesPerRing: nPerRing,      // e.g., [0, 5, 12, 18, ...]
        ringSigmaRatios: ringRatios,  // e.g., [0.05, 0.10, 0.15, ...] (optional)
);



      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: ${file.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<Uint8List?> _captureChartPng() async {
    final boundary = _chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}

// ==========================
// Interactive Chart & Math
// ==========================

class _InteractiveChart extends StatefulWidget {
  const _InteractiveChart({
    required this.width,
    required this.height,
    required this.z,
    required this.deltaSOverQ,
    required this.sMax,
    required this.nr,
    required this.shape,
    required this.L,
    required this.B,
    required this.D,
    required this.a,
    required this.polygonPoints,
    required this.scale,
    required this.rotDeg,
    required this.shift,
    required this.onPoseChanged,
    required this.qkPa,
  });

  final double width;
  final double height;
  final double z;
  final double deltaSOverQ;
  final double sMax;
  final int nr;
  final FootingShape shape;
  final double L, B, D, a;
  final List<Offset> polygonPoints;
  final double scale;
  final double rotDeg;
  final Offset shift; // meters
  final void Function(double scale, double rotDeg, Offset shift, double N, double sigma) onPoseChanged;
  final double qkPa;

  @override
  State<_InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<_InteractiveChart> {
  late double _scale;
  late double _rotDeg;
  late Offset _shift;

  late List<double> _radii; // meters
  late List<double> _ringTargets; // s = σz/q values for rings

  @override
  void initState() {
    super.initState();
    _scale = widget.scale;
    _rotDeg = widget.rotDeg;
    _shift = widget.shift;
    _computeRings();
  }

  @override
void didUpdateWidget(covariant _InteractiveChart oldWidget) {
  super.didUpdateWidget(oldWidget);

  // Rebuild rings if chart params changed
  if (oldWidget.z != widget.z ||
      oldWidget.deltaSOverQ != widget.deltaSOverQ ||
      oldWidget.sMax != widget.sMax ||
      oldWidget.nr != widget.nr) {
    _computeRings();
  }

  // ✅ keep pose in sync with parent
  if (oldWidget.rotDeg != widget.rotDeg) _rotDeg = widget.rotDeg;
  if (oldWidget.scale  != widget.scale)  _scale  = widget.scale;
  if (oldWidget.shift  != widget.shift)  _shift  = widget.shift;

  // Update HUD when pose changes from parent
  if (oldWidget.rotDeg != widget.rotDeg ||
      oldWidget.scale  != widget.scale  ||
      oldWidget.shift  != widget.shift) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHUD());
  }
}


  void _computeRings() {
    _radii = [];
    _ringTargets = [];
    final nRings = math.max((widget.sMax / widget.deltaSOverQ + 1e-12).floor(), 1);
    for (int i = 1; i <= nRings; i++) {
      final s = i * widget.deltaSOverQ; // σz/q at ring i
      final r = _radiusForSigmaRatio(s, widget.z);
      if (r.isFinite) {
        _radii.add(r);
        _ringTargets.add(s);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHUD());
  }

  double _radiusForSigmaRatio(double sRatio, double z) {
    if (sRatio <= 0 || sRatio >= 1) return double.infinity;
    final val = math.pow(1.0 / (1.0 - sRatio), 2.0 / 3.0) - 1.0;
    if (val <= 0) return 0.0;
    return z * math.sqrt(val);
  }

  // Build sector centers for Newmark counting (r, theta)
  List<Offset> _sectorCenters() {
    final List<Offset> centers = [];
    final List<double> edges = [0.0, ..._radii];
    for (int i = 0; i < edges.length - 1; i++) {
      final r0 = edges[i];
      final r1 = edges[i + 1];
      final rMid = (r0 + r1) / 2;
      for (int j = 0; j < widget.nr; j++) {
        final th0 = 2 * math.pi * j / widget.nr;
        final th1 = 2 * math.pi * (j + 1) / widget.nr;
        final thMid = (th0 + th1) / 2;
        centers.add(Offset(rMid * math.cos(thMid), rMid * math.sin(thMid)));
      }
    }
    return centers;
  }

  // Footing path in chart coordinates (meters), centered at origin then transformed
  ui.Path _footingPath() {
    final path = ui.Path();
    switch (widget.shape) {
      case FootingShape.circular:
        final r = (widget.D / 2) * _scale;
        path.addOval(Rect.fromCircle(center: Offset.zero, radius: r));
        break;
      case FootingShape.square:
        final s = (widget.a * _scale);
        final rect = Rect.fromCenter(center: Offset.zero, width: s, height: s);
        path.addRect(rect);
        break;
      case FootingShape.rectangular:
        final w = (widget.L * _scale);
        final h = (widget.B * _scale);
        final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
        path.addRect(rect);
        break;
      case FootingShape.polygon:
        final poly = PolygonFooting.pathCentered(widget.polygonPoints);
        final mScale = Matrix4.identity()..scale(_scale, _scale);
        path.addPath(poly.transform(mScale.storage), Offset.zero);
        break;
    }
    final m = Matrix4.identity()
  ..rotateZ(_rotDeg * math.pi / 180.0) // rotate around origin
  ..translate(_shift.dx, _shift.dy);   // then move it
return path.transform(m.storage);
  }

  // Compute N by counting centers inside footing path
  double _computeN() {
    final centers = _sectorCenters();
    final footing = _footingPath();
    int count = 0;
    for (final c in centers) {
      if (_pointInPath(footing, c)) count++;
    }
    return count.toDouble();
  }

  // Point-in-path hit test via tiny circle intersection
  bool _pointInPath(ui.Path path, Offset p) {
    final tp = ui.Path()..addOval(Rect.fromCircle(center: p, radius: 0.001));
    final op = ui.Path.combine(ui.PathOperation.intersect, path, tp);
    final bounds = op.getBounds();
    return bounds.width > 0 && bounds.height > 0;
  }

  void _updateHUD() {
    final influenceFactor = widget.nr > 0 ? (widget.deltaSOverQ / widget.nr) : 0.0;
    final N = _computeN();
    final sigma = influenceFactor * N * widget.qkPa; // kPa
    widget.onPoseChanged(_scale, _rotDeg, _shift, N, sigma);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // meters-to-pixels scale so that outer ring fits nicely
    final outerR = _radii.isEmpty ? widget.z : _radii.last;
    final pxPerMeter = math.min(widget.width, widget.height) * 0.42 / (outerR == 0 ? 1 : outerR);

    return GestureDetector(
      onScaleUpdate: (details) {
        // Use focalPointDelta (in px) -> convert to meters
        final dxm = details.focalPointDelta.dx / pxPerMeter;
        final dym = details.focalPointDelta.dy / pxPerMeter;
        _shift += Offset(dxm, dym);
        _scale *= details.scale.clamp(0.8, 1.25);
        _rotDeg += details.rotation * 180 / math.pi;
        _updateHUD();
      },
      child: CustomPaint(
        painter: _ChartPainter(
          radii: _radii,
          nr: widget.nr,
          z: widget.z,
          pxPerMeter: pxPerMeter,
          footingPathMeters: _footingPath(),
          N: _computeN(),
          influenceFactor: widget.deltaSOverQ / (widget.nr > 0 ? widget.nr : 1),
          qkPa: widget.qkPa,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.radii,
    required this.nr,
    required this.z,
    required this.pxPerMeter,
    required this.footingPathMeters,
    required this.N,
    required this.influenceFactor,
    required this.qkPa,
  });

  final List<double> radii; // meters
  final int nr;
  final double z; // meters
  final double pxPerMeter;
  final ui.Path footingPathMeters; // path in meter units
  final double N;
  final double influenceFactor;
  final double qkPa;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Convert meter path to pixel path (translate + scale)
    final meterToPx = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..scale(pxPerMeter, pxPerMeter);
    final footingPx = footingPathMeters.transform(meterToPx.storage);

    // Background (transparent)
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.transparent);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.grey.withValues(alpha: 0.6); // instead of withOpacity

    // Rings
    for (final R in radii) {
      canvas.drawCircle(center, R * pxPerMeter, grid);
    }

    // Radial lines
    final rMax = (radii.isEmpty ? z : radii.last) * 2.2; // VIEW_RADIUS_FACTOR
    for (int k = 0; k < nr; k++) {
      final th = 2 * math.pi * k / nr;
      final p = center + Offset(rMax * math.cos(th), rMax * math.sin(th)) * pxPerMeter;
      canvas.drawLine(center, p, grid);
    }

    // AB = z bar
    canvas.drawLine(
      center,
      center + Offset(z * pxPerMeter, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // POI
    canvas.drawCircle(center, 4, Paint()..style = PaintingStyle.fill);

    // Footing
    final footingFill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.12);
    final footingStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black87;
    canvas.drawPath(footingPx, footingFill);
    canvas.drawPath(footingPx, footingStroke);

    // HUD
    final sigma = influenceFactor * N * qkPa;
    TextPainter tp(String s) => TextPainter(
          text: TextSpan(
            text: s,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 260);

    final lines = <String>[
      'Live',
      'N = ${N.toStringAsFixed(3)}',
      'σz = ${sigma.isFinite ? sigma.toStringAsFixed(3) : '—'} kPa',
      'If = ${influenceFactor.toStringAsFixed(5)} | q = ${qkPa.toStringAsFixed(3)} kPa | z = ${z.toStringAsFixed(3)} m',
    ];
    const padding = 8.0;
    final tps = lines.map(tp).toList();
    final w = tps.map((e) => e.width).reduce(math.max) + padding * 2;
    final h = tps.fold<double>(0, (a, b) => a + b.height) + padding * 2 + 8;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(12, 12, w, h),
      const Radius.circular(10),
    );
    canvas.drawRRect(rrect, Paint()..color = Colors.white.withValues(alpha: 0.75));

    double y = 12 + padding;
    for (final t in tps) {
      t.paint(canvas, Offset(12 + padding, y));
      y += t.height + 4;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter o) =>
      o.radii != radii ||
      o.nr != nr ||
      o.z != z ||
      o.pxPerMeter != pxPerMeter ||
      o.footingPathMeters != footingPathMeters ||
      o.N != N ||
      o.influenceFactor != influenceFactor ||
      o.qkPa != qkPa;
}
