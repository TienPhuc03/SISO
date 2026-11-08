/// Số liệu một khung hình, lấy từ `FrameTiming` của Flutter (cùng nguồn với tab Performance của DevTools).
class FrameSample {
  const FrameSample({required this.vsyncStartUs, required this.buildUs, required this.rasterUs});

  /// Mốc vsync bắt đầu khung (micro giây, đồng hồ đơn điệu của engine).
  final int vsyncStartUs;

  /// Thời gian luồng UI dựng khung (build + layout + paint).
  final int buildUs;

  /// Thời gian luồng raster vẽ khung lên GPU.
  final int rasterUs;

  /// Khung chậm hơn ngân sách khi một trong hai luồng vượt ngân sách.
  int get costUs => buildUs > rasterUs ? buildUs : rasterUs;
}

/// Kết quả một lượt đo.
class FrameStats {
  const FrameStats({
    required this.frames,
    required this.fps,
    required this.jankPercent,
    required this.p90BuildMs,
    required this.p90RasterMs,
    required this.worstFrameMs,
  });

  final int frames;

  /// FPS trong lúc bản đồ đang chuyển động (bỏ các khoảng nghỉ không có khung nào).
  final double fps;

  /// % số khung vượt ngân sách 16,7 ms (khung giật).
  final double jankPercent;
  final double p90BuildMs;
  final double p90RasterMs;
  final double worstFrameMs;

  /// Tiêu chí Milestone 1 / NFR-02: trung bình ≥ 55 FPS.
  static const double targetFps = 55;
  bool get passed => frames > 0 && fps >= targetFps;

  static const empty = FrameStats(
    frames: 0,
    fps: 0,
    jankPercent: 0,
    p90BuildMs: 0,
    p90RasterMs: 0,
    worstFrameMs: 0,
  );

  /// Ngân sách một khung ở 60 Hz.
  static const int frameBudgetUs = 16667;

  /// Khoảng cách giữa hai khung lớn hơn mức này coi như bản đồ đang đứng yên
  /// (Flutter không vẽ khung khi không có gì đổi), không tính vào FPS.
  static const int idleGapUs = 100000;

  static FrameStats from(List<FrameSample> samples) {
    if (samples.isEmpty) return empty;
    final sorted = [...samples]..sort((a, b) => a.vsyncStartUs.compareTo(b.vsyncStartUs));

    var activeUs = 0;
    var activeGaps = 0;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].vsyncStartUs - sorted[i - 1].vsyncStartUs;
      if (gap > 0 && gap <= idleGapUs) {
        activeUs += gap;
        activeGaps++;
      }
    }
    final fps = activeUs == 0 ? 0.0 : activeGaps * 1e6 / activeUs;

    final janky = samples.where((s) => s.costUs > frameBudgetUs).length;
    return FrameStats(
      frames: samples.length,
      fps: fps,
      jankPercent: janky * 100 / samples.length,
      p90BuildMs: _p90([for (final s in samples) s.buildUs]) / 1000,
      p90RasterMs: _p90([for (final s in samples) s.rasterUs]) / 1000,
      worstFrameMs: samples.map((s) => s.costUs).reduce((a, b) => a > b ? a : b) / 1000,
    );
  }

  static int _p90(List<int> values) {
    final v = [...values]..sort();
    return v[((v.length - 1) * 0.9).round()];
  }
}
