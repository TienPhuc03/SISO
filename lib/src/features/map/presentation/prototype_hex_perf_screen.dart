// ⚠️ PROTOTYPE, VỨT ĐI SAU KHI CHỐT. Ticket wayfinder #6 (TienPhuc03/SISO).
// Câu hỏi: tải và vẽ ~500 ô H3 res 10 ở 55–60 FPS thế nào?
//   A = dựng polygon cả Đấu trường MỘT lần, cache ranh giới ô
//   B = dựng lại polygon các ô trong viewport MỖI LẦN camera đổi (mô phỏng tải theo viewport)
//   C = như A, nhưng chuyển GPS → H3 trong Isolate (compute)
// Dữ liệu giả, không gọi backend, không lưu gì. Không dùng trong app thật.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:latlong2/latlong.dart';

enum Variant { a, b, c }

const _center = LatLng(10.7951, 106.7219); // Landmark 81
const _uniColors = [
  Color(0xFFE53935), // HUTECH
  Color(0xFF1E88E5), // UEF
  Color(0xFF43A047), // UT
  Color(0xFFFDD835), // FTU
  Color(0xFF8E24AA), // HIU
];

/// Chạy trong Isolate cho biến thể C (trên web, compute chạy ngay trên main thread).
BigInt _latLngToCellIsolate(List<double> latLng) =>
    const H3Factory().load().geoToH3(GeoCoord(lon: latLng[1], lat: latLng[0]), 10);

class PrototypeHexPerfScreen extends StatefulWidget {
  const PrototypeHexPerfScreen({super.key});

  @override
  State<PrototypeHexPerfScreen> createState() => _PrototypeHexPerfScreenState();
}

class _PrototypeHexPerfScreenState extends State<PrototypeHexPerfScreen> {
  final H3 _h3 = const H3Factory().load();
  final _map = MapController();
  final _rng = Random(42);

  Variant _variant = Variant.values.firstWhere(
    (v) => v.name == Uri.base.queryParameters['variant'],
    orElse: () => Variant.a,
  );
  int _ringSize = 13; // k=13 → 547 ô; k=26 → 2107 ô
  List<BigInt> _cells = [];
  final Map<BigInt, int> _owner = {};
  final Map<BigInt, List<LatLng>> _boundaryCache = {};
  List<Polygon> _polygons = [];

  // Số đo hiển thị
  double _lastPolygonBuildMs = 0;
  double _initialLoadMs = 0;
  double _gpsConvMs = 0;
  String _gpsCell = '-';
  int _fps = 0;
  double _worstFrameGapMs = 0;
  int _jankFrames = 0;
  double _worstBuildMs = 0, _worstRasterMs = 0;
  bool _timingsAvailable = false;

  // Đo khung hình
  Duration? _lastFrameTs;
  int _framesThisSecond = 0;
  double _worstGapThisSecond = 0;
  int _jankThisSecond = 0;
  double _buildThisSecond = 0, _rasterThisSecond = 0;
  Timer? _secondTicker;

  // Mô phỏng chuyển động
  bool _autoPan = true;
  Timer? _panTimer;
  double _panT = 0;
  Timer? _gpsTimer;
  LatLng _gps = _center;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _loadCells();
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _secondTicker = Timer.periodic(const Duration(seconds: 1), (_) => _rollSecond());
    _startPan();
    _gpsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickGps());
  }

  @override
  void dispose() {
    _secondTicker?.cancel();
    _panTimer?.cancel();
    _gpsTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  // ---------- Dữ liệu ----------

  void _loadCells() {
    final sw = Stopwatch()..start();
    final origin = _h3.geoToH3(GeoCoord(lon: _center.longitude, lat: _center.latitude), 10);
    _cells = _h3.kRing(origin, _ringSize);
    _owner.clear();
    for (final c in _cells) {
      _owner[c] = _rng.nextInt(6) - 1; // -1 = chưa ai chiếm
    }
    _boundaryCache.clear();
    if (_variant != Variant.b) {
      for (final c in _cells) {
        _boundaryCache[c] = _boundaryOf(c);
      }
    }
    _initialLoadMs = sw.elapsedMicroseconds / 1000;
    _rebuildPolygons();
  }

  List<LatLng> _boundaryOf(BigInt cell) =>
      _h3.h3ToGeoBoundary(cell).map((g) => LatLng(g.lat, g.lon)).toList(growable: false);

  Polygon _polygonFor(BigInt cell, List<LatLng> pts) {
    final o = _owner[cell] ?? -1;
    return Polygon(
      points: pts,
      color: o < 0 ? Colors.white.withValues(alpha: 0.06) : _uniColors[o].withValues(alpha: 0.45),
      borderColor: Colors.white24,
      borderStrokeWidth: 1,
    );
  }

  void _rebuildPolygons({LatLngBounds? viewport}) {
    final sw = Stopwatch()..start();
    if (_variant == Variant.b) {
      // Mô phỏng "tải theo viewport": mỗi lần camera đổi, lọc ô trong khung nhìn và tính lại ranh giới
      final bounds = viewport ?? (_mapReady ? _map.camera.visibleBounds : null);
      final result = <Polygon>[];
      for (final c in _cells) {
        final g = _h3.h3ToGeo(c);
        if (bounds == null || bounds.contains(LatLng(g.lat, g.lon))) {
          result.add(_polygonFor(c, _boundaryOf(c)));
        }
      }
      _polygons = result;
    } else {
      _polygons = [for (final c in _cells) _polygonFor(c, _boundaryCache[c]!)];
    }
    _lastPolygonBuildMs = sw.elapsedMicroseconds / 1000;
  }

  void _claimRandom50() {
    final uni = _rng.nextInt(_uniColors.length);
    for (var i = 0; i < 50; i++) {
      _owner[_cells[_rng.nextInt(_cells.length)]] = uni;
    }
    setState(_rebuildPolygons);
  }

  Future<void> _tickGps() async {
    _gps = LatLng(
      _gps.latitude + (_rng.nextDouble() - 0.5) * 0.0002,
      _gps.longitude + (_rng.nextDouble() - 0.5) * 0.0002,
    );
    final sw = Stopwatch()..start();
    final BigInt cell;
    if (_variant == Variant.c) {
      cell = await compute(_latLngToCellIsolate, [_gps.latitude, _gps.longitude]);
    } else {
      cell = _h3.geoToH3(GeoCoord(lon: _gps.longitude, lat: _gps.latitude), 10);
    }
    if (!mounted) return;
    setState(() {
      _gpsConvMs = sw.elapsedMicroseconds / 1000;
      _gpsCell = cell.toRadixString(16);
    });
  }

  // ---------- Camera ----------

  void _startPan() {
    _panTimer?.cancel();
    if (!_autoPan) return;
    _panTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_mapReady) return;
      _panT += 0.02;
      _map.move(
        LatLng(_center.latitude + 0.004 * sin(_panT), _center.longitude + 0.004 * cos(_panT)),
        15.5 + 0.5 * sin(_panT / 3),
      );
    });
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (_variant == Variant.b) {
      setState(() => _rebuildPolygons(viewport: camera.visibleBounds));
    }
  }

  // ---------- Đo FPS ----------

  void _onFrame(Duration ts) {
    if (_lastFrameTs != null) {
      final gapMs = (ts - _lastFrameTs!).inMicroseconds / 1000;
      if (gapMs < 500) {
        // bỏ qua khoảng nghỉ khi không có gì vẽ
        _framesThisSecond++;
        if (gapMs > _worstGapThisSecond) _worstGapThisSecond = gapMs;
        if (gapMs > 20) _jankThisSecond++;
      }
    }
    _lastFrameTs = ts;
  }

  void _onTimings(List<FrameTiming> timings) {
    _timingsAvailable = true;
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds / 1000;
      final r = t.rasterDuration.inMicroseconds / 1000;
      if (b > _buildThisSecond) _buildThisSecond = b;
      if (r > _rasterThisSecond) _rasterThisSecond = r;
    }
  }

  void _rollSecond() {
    if (!mounted) return;
    setState(() {
      _fps = _framesThisSecond;
      _worstFrameGapMs = _worstGapThisSecond;
      _jankFrames = _jankThisSecond;
      _worstBuildMs = _buildThisSecond;
      _worstRasterMs = _rasterThisSecond;
    });
    _framesThisSecond = 0;
    _worstGapThisSecond = 0;
    _jankThisSecond = 0;
    _buildThisSecond = 0;
    _rasterThisSecond = 0;
  }

  // ---------- UI ----------

  void _setVariant(Variant v) {
    setState(() {
      _variant = v;
      _loadCells();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15.5,
              onMapReady: () {
                _mapReady = true;
                if (_variant == Variant.b) setState(_rebuildPolygons);
              },
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.siso.prototype',
              ),
              RepaintBoundary(
                child: PolygonLayer(polygons: _polygons, polygonLabels: false),
              ),
              MarkerLayer(markers: [
                Marker(
                  point: _gps,
                  width: 14,
                  height: 14,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle),
                  ),
                ),
              ]),
            ],
          ),
          Positioned(top: 12, left: 12, child: _statePanel()),
          Positioned(left: 0, right: 0, bottom: 12, child: _bottomBar()),
        ],
      ),
    );
  }

  Widget _statePanel() {
    final ok = _fps >= 55;
    String ms(double v) => '${v.toStringAsFixed(2)} ms';
    final rows = <String, String>{
      'Biến thể': switch (_variant) {
        Variant.a => 'A · cả Đấu trường, dựng 1 lần',
        Variant.b => 'B · dựng lại theo viewport mỗi lần camera đổi',
        Variant.c => 'C · như A + GPS→H3 trong Isolate',
      },
      'Nền tảng': kIsWeb ? 'Web (Isolate = main thread)' : defaultTargetPlatform.name,
      'Chế độ build': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug (FPS không đáng tin)'),
      'Số ô tổng': '${_cells.length}',
      'Số polygon đang vẽ': '${_polygons.length}',
      'Tải ban đầu': ms(_initialLoadMs),
      'Dựng polygon lần cuối': ms(_lastPolygonBuildMs),
      'GPS→H3 lần cuối': '${ms(_gpsConvMs)} → $_gpsCell',
      'FPS (1s gần nhất)': '$_fps ${ok ? "✅" : "❌"}',
      'Khoảng hở khung tệ nhất': ms(_worstFrameGapMs),
      'Khung > 20 ms': '$_jankFrames',
      'Build / raster tệ nhất': _timingsAvailable ? '${ms(_worstBuildMs)} / ${ms(_worstRasterMs)}' : 'không có FrameTiming',
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PROTOTYPE #6, vứt đi', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            for (final e in rows.entries) Text('${e.key}: ${e.value}'),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(24)),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<Variant>(
              segments: const [
                ButtonSegment(value: Variant.a, label: Text('A')),
                ButtonSegment(value: Variant.b, label: Text('B')),
                ButtonSegment(value: Variant.c, label: Text('C')),
              ],
              selected: {_variant},
              onSelectionChanged: (s) => _setVariant(s.first),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 13, label: Text('~500 ô')),
                ButtonSegment(value: 26, label: Text('~2000 ô')),
              ],
              selected: {_ringSize},
              onSelectionChanged: (s) => setState(() {
                _ringSize = s.first;
                _loadCells();
              }),
            ),
            FilterChip(
              label: const Text('Tự lia camera'),
              selected: _autoPan,
              onSelected: (v) {
                setState(() => _autoPan = v);
                _startPan();
              },
            ),
            FilledButton(onPressed: _claimRandom50, child: const Text('Chiếm 50 ô')),
          ],
        ),
      ),
    );
  }
}
