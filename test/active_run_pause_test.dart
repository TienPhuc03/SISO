import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/features/tracking/data/telemetry_repository.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_window.dart';
import 'package:siso_project/src/features/tracking/presentation/active_run_screen.dart';
import 'package:siso_project/src/features/tracking/providers/tracking_session_notifier.dart';

class _Source implements TelemetryWindowSource {
  final win = StreamController<TelemetryWindow>.broadcast();
  int starts = 0;
  int stops = 0;

  @override
  Stream<double> get speedMps => const Stream.empty();
  @override
  Stream<TelemetryWindow> get windows => win.stream;
  @override
  Stream<GpsFix> get positions => const Stream.empty();
  @override
  void start() => starts++;
  @override
  void stop() => stops++;
}

class _Repo extends TelemetryRepository {
  @override
  Future<VerifyWindowResult> verifyWindow(TelemetryWindow window,
          {String? sessionId, String? signingKey, int? seq}) async =>
      const VerifyWindowResult(
        sessionId: 'ce79387c-d256-40ab-825d-53ba90e16e74',
        signingKey: 'k',
        windowPassed: true,
        consecutiveFailures: 0,
        biometricApplied: true,
        cadenceSpm: 160,
        message: '',
      );

  @override
  Future<double> finishSession(String sessionId) async => 0.5;
}

void main() {
  testWidgets('đang chạy: Tạm dừng thì đồng hồ đứng yên, Tiếp tục thì chạy tiếp; không hiện mã Phiên chạy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final source = _Source();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allowFakeSourcesProvider.overrideWithValue(false),
        telemetryWindowSourceProvider.overrideWithValue(source),
        telemetryRepositoryProvider.overrideWithValue(_Repo()),
      ],
      child: const MaterialApp(home: ActiveRunScreen()),
    ));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    source.win.add(const TelemetryWindow(samples: [], averageSpeedMps: 3, horizontalAccuracy: 5, isMocked: false));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:02'), findsOneWidget);
    // Mã Phiên chạy chỉ có ích cho nhóm phát triển, không hiện cho Sinh viên.
    expect(find.textContaining('ce79387c'), findsNothing);

    await tester.tap(find.byKey(const Key('run_pause')));
    await tester.pump();
    expect(find.text('Tiếp tục'), findsOneWidget);
    expect(find.text('Tạm dừng'), findsWidgets); // nhãn trạng thái trên bản đồ
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('00:02'), findsOneWidget, reason: 'Tạm dừng không tính thời gian');

    await tester.tap(find.byKey(const Key('run_resume')));
    await tester.pump();
    expect(source.starts, 2);
    expect(find.byKey(const Key('run_pause')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:04'), findsOneWidget);

    // Nút Kết thúc vẫn còn khi đang chạy
    await tester.tap(find.byKey(const Key('run_stop')));
    await tester.pump();
  });

  testWidgets('đang Tạm dừng vẫn bấm Kết thúc được', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final source = _Source();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allowFakeSourcesProvider.overrideWithValue(false),
        telemetryWindowSourceProvider.overrideWithValue(source),
        telemetryRepositoryProvider.overrideWithValue(_Repo()),
      ],
      child: const MaterialApp(home: ActiveRunScreen()),
    ));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    source.win.add(const TelemetryWindow(samples: [], averageSpeedMps: 3, horizontalAccuracy: 5, isMocked: false));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('run_pause')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('run_stop')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('run_pause')), findsNothing);
    expect(find.byKey(const Key('run_resume')), findsNothing);
  });
}
