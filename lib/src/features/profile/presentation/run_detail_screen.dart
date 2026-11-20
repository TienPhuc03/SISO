import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/siso_theme.dart';
import '../../tracking/presentation/active_run_screen.dart' show formatDuration, formatPace;
import '../domain/profile_models.dart';
import '../providers/profile_providers.dart';
import 'profile_screen.dart' show formatRunDate, runStatusBadge;

/// Chi tiết một Phiên chạy trong Lịch sử: Đường chạy, số liệu, và xuất cả thẻ thành ảnh PNG.
class RunDetailScreen extends ConsumerStatefulWidget {
  const RunDetailScreen({super.key, required this.sessionId, this.tileProvider});

  final String sessionId;

  /// Nguồn tile nền; `null` = tải qua mạng. Test truyền nguồn giả để không gọi mạng.
  final TileProvider? tileProvider;

  @override
  ConsumerState<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends ConsumerState<RunDetailScreen> {
  final _cardKey = GlobalKey();
  bool _exporting = false;

  String get _fileName => 'siso_phien_chay_${widget.sessionId}';

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Chụp thẻ (đúng như đang hiện) thành PNG.
  Future<Uint8List> _renderPng() async {
    final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }

  /// Hỏi lưu vào thư viện ảnh hay mở bảng chia sẻ.
  Future<void> _export() async {
    final saveToGallery = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('export_save'),
              leading: const Icon(Icons.download_outlined),
              title: const Text('Lưu vào thư viện ảnh'),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              key: const Key('export_share'),
              leading: const Icon(Icons.ios_share),
              title: const Text('Chia sẻ…'),
              subtitle: const Text('Zalo, Messenger, Instagram…'),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
    if (saveToGallery == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final png = await _renderPng();
      saveToGallery ? await _save(png) : await _share(png);
    } catch (e) {
      _toast('Không xuất được ảnh: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _save(Uint8List png) async {
    // Xin quyền ngay lúc lưu, không xin lúc cài app. Android 10+ không cần quyền nên không hiện hộp thoại.
    if (!await Gal.hasPermission() && !await Gal.requestPermission()) {
      return _toast('Chưa có quyền lưu ảnh. Bật quyền Ảnh cho SISO trong Cài đặt của máy.');
    }
    await Gal.putImageBytes(png, name: _fileName);
    _toast('Đã lưu vào thư viện ảnh.');
  }

  Future<void> _share(Uint8List png) async {
    final file = File('${(await getTemporaryDirectory()).path}/$_fileName.png');
    await file.writeAsBytes(png);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      // iPad cần điểm neo cho bảng chia sẻ.
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(runDetailProvider(widget.sessionId));
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: SisoColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  SisoCircleButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Quay lại',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 14),
                  const Text('Chi tiết Phiên chạy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: detail.when(
                data: (d) => ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    RepaintBoundary(
                      key: _cardKey,
                      child: RunShareCard(
                        detail: d,
                        runnerName: profile?.displayName,
                        campusCode: profile?.campusShortCode,
                        tileProvider: widget.tileProvider,
                      ),
                    ),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(runDetailProvider(widget.sessionId)),
                    child: const Text('Không tải được Phiên chạy. Thử lại'),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton.icon(
                key: const Key('run_export'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: detail.hasValue && !_exporting ? _export : null,
                icon: _exporting
                    ? const SizedBox.square(
                        dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.ios_share),
                label: const Text('Xuất ảnh'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ tổng kết Phiên chạy: phần được chụp thành ảnh khi xuất.
class RunShareCard extends StatelessWidget {
  const RunShareCard({super.key, required this.detail, this.runnerName, this.campusCode, this.tileProvider});

  final RunDetail detail;
  final String? runnerName;
  final String? campusCode;
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    final run = detail.summary;
    final (statusText, statusColor) = runStatusBadge(run);
    final route = detail.route;
    final points = [for (final s in route) ...s];
    final cadence = detail.avgCadence;

    return Container(
      decoration: sisoCard(radius: 20).copyWith(color: SisoColors.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: points.length < 2
                ? Container(
                    color: SisoColors.tint,
                    alignment: Alignment.center,
                    child: const Text('Không có Đường chạy để hiển thị',
                        style: TextStyle(color: SisoColors.body, fontSize: 13)),
                  )
                : FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(28)),
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: AppConstants.mapTileUrl,
                        userAgentPackageName: 'com.siso.app',
                        tileProvider: tileProvider,
                      ),
                      PolylineLayer(polylines: [
                        for (final segment in route)
                          Polyline(
                            points: segment,
                            strokeWidth: 5,
                            color: SisoColors.primary,
                            borderStrokeWidth: 1.5,
                            borderColor: Colors.white,
                          ),
                      ]),
                      CircleLayer(circles: [
                        _dot(points.first, SisoColors.successText),
                        _dot(points.last, SisoColors.danger),
                      ]),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const HexIcon(size: 16, color: SisoColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          'SISO',
                          if (runnerName != null && runnerName!.isNotEmpty) runnerName!,
                          if (campusCode != null) campusCode!,
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(formatRunDate(run.startedAt), style: const TextStyle(fontSize: 12, color: SisoColors.body)),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    _Stat(label: 'Quãng đường', value: viDecimal(run.km, 2), unit: 'km'),
                    _Stat(label: 'Thời gian', value: formatDuration(run.durationSeconds)),
                    _Stat(label: 'Pace', value: formatPace(run.avgSpeedKmh), unit: '/km'),
                    _Stat(label: 'Tốc độ TB', value: viDecimal(run.avgSpeedKmh), unit: 'km/h'),
                    _Stat(label: 'Nhịp bước TB', value: cadence?.toString() ?? '--', unit: 'SPM'),
                    _Stat(label: 'Cửa sổ hợp lệ', value: '${detail.validWindows}/${detail.windows.length}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static CircleMarker _dot(LatLng point, Color color) =>
      CircleMarker(point: point, radius: 6, color: color, borderColor: Colors.white, borderStrokeWidth: 2);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: SisoColors.caption)),
        Text.rich(
          TextSpan(text: value, children: [
            if (unit != null) TextSpan(text: ' $unit', style: const TextStyle(fontSize: 11, color: SisoColors.body)),
          ]),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
