import 'package:flutter/material.dart';

import '../../../core/theme/siso_theme.dart';

enum SisoTab { map, leaderboard }

/// Thanh điều hướng nổi: Bản đồ · nút tròn "Chạy" nhô lên · Xếp hạng.
class SisoBottomNav extends StatelessWidget {
  const SisoBottomNav({
    super.key,
    required this.active,
    required this.onMap,
    required this.onRun,
    required this.onLeaderboard,
    this.onRunLongPress,
  });

  final SisoTab active;
  final VoidCallback onMap;
  final VoidCallback onRun;
  final VoidCallback onLeaderboard;

  /// Nhấn giữ nút "Chạy" mở màn Ghi log cảm biến (issue #8; ẩn, dùng được cả bản release IPA).
  final VoidCallback? onRunLongPress;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          height: 92,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 66,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: sisoCard().copyWith(
                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 28, offset: Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _Tab(
                        icon: Icons.map_outlined,
                        label: 'Bản đồ',
                        active: active == SisoTab.map,
                        onTap: onMap,
                      ),
                    ),
                    const SizedBox(width: 78),
                    Expanded(
                      child: _Tab(
                        key: const Key('leaderboard_button'),
                        icon: Icons.bar_chart_rounded,
                        label: 'Xếp hạng',
                        active: active == SisoTab.leaderboard,
                        onTap: onLeaderboard,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                child: GestureDetector(
                  key: const Key('run_fab_hold'),
                  onLongPress: onRunLongPress,
                  child: Material(
                    color: SisoColors.primary,
                    shape: const CircleBorder(),
                    elevation: 6,
                    shadowColor: const Color(0x61008689),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onRun,
                      child: const SizedBox.square(
                        dimension: 62,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_run, color: Colors.white, size: 24),
                            Text('Chạy',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({super.key, required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? SisoColors.primary : SisoColors.body;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
