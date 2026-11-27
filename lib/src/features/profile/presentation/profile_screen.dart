import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../../../core/theme/siso_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/domain/hex_cell.dart' show parseHexColor;
import '../../university/presentation/university_picker_screen.dart';
import '../../tracking/presentation/active_run_screen.dart' show formatDuration;
import '../domain/profile_models.dart';
import '../providers/profile_providers.dart';
import 'avatar_view.dart';
import 'run_detail_screen.dart';

/// Hồ sơ của chính Sinh viên: ảnh đại diện, nickname, Km cá nhân và Lịch sử Phiên chạy.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.imagePicker});

  /// Test truyền bộ chọn ảnh giả.
  final ImagePicker? imagePicker;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _saving = false;

  void _showError(Object error) {
    if (!mounted) return;
    final text = error is SisoException ? error.message : 'Không kết nối được máy chủ. Thử lại sau.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      ref.invalidate(profileProvider);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    // Thu nhỏ ngay trên máy: ảnh gửi đi khoảng 50 KB, dưới trần 512 KB của server.
    final file = await (widget.imagePicker ?? ImagePicker())
        .pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (file == null) return;
    await _run(() async => ref.read(profileRepositoryProvider).uploadAvatar(await file.readAsBytes(), file.name));
  }

  Future<void> _editName(String current) async {
    final name = await showDialog<String>(context: context, builder: (_) => _NicknameDialog(initial: current));
    if (name == null || name == current) return;
    if (name.length < 2) return _showError(const SisoException(code: 'HTTP_400', message: 'Nickname cần ít nhất 2 ký tự.'));
    await _run(() => ref.read(profileRepositoryProvider).updateDisplayName(name));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final runs = ref.watch(runHistoryProvider);
    final session = ref.watch(authSessionProvider);
    final canChange = session is AuthSignedIn && session.user.university != null && session.user.canChangeUniversity;

    return Scaffold(
      backgroundColor: SisoColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(runHistoryProvider);
            await ref.read(runHistoryProvider.future).catchError((_) => <RunSummary>[]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Row(
                children: [
                  SisoCircleButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Quay lại',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 14),
                  const Text('Hồ sơ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),
              profile.when(
                data: (p) => _ProfileCard(
                  profile: p,
                  saving: _saving,
                  onPickAvatar: _saving ? null : _pickAvatar,
                  onEditName: _saving ? null : () => _editName(p.displayName),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _ErrorBox(onRetry: () => ref.invalidate(profileProvider)),
              ),
              if (canChange)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('profile_change_university'),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Đổi Trường (trước Phiên chạy đầu tiên của Mùa)'),
                    onPressed: () async {
                      await Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const UniversityPickerScreen()));
                      ref.invalidate(profileProvider);
                    },
                  ),
                ),
              const SizedBox(height: 22),
              const Text('Lịch sử Phiên chạy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...runs.when(
                data: (list) => list.isEmpty
                    ? [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('Chưa có Phiên chạy nào. Bấm "Chạy" để bắt đầu.',
                              textAlign: TextAlign.center, style: TextStyle(color: SisoColors.body)),
                        ),
                      ]
                    : [for (final run in list) _RunTile(run: run)],
                loading: () => [
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                ],
                error: (e, _) => [_ErrorBox(onRetry: () => ref.invalidate(runHistoryProvider))],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hộp thoại đổi nickname; giữ controller tới khi hộp thoại đóng hẳn (hết hiệu ứng).
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đổi nickname'),
      content: TextField(
        key: const Key('nickname_field'),
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(hintText: '2–30 ký tự'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
        FilledButton(
          key: const Key('nickname_save'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.saving, this.onPickAvatar, this.onEditName});

  final Profile profile;
  final bool saving;
  final VoidCallback? onPickAvatar;
  final VoidCallback? onEditName;

  @override
  Widget build(BuildContext context) {
    final name = profile.displayName.isEmpty ? profile.email.split('@').first : profile.displayName;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: sisoCard(radius: 20),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Đổi ảnh đại diện',
                child: GestureDetector(
                  key: const Key('avatar_pick'),
                  onTap: onPickAvatar,
                  child: Stack(
                    children: [
                      AvatarView(url: profile.avatarUrl, name: name, size: 72),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: SisoColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: saving
                              ? const SizedBox.square(
                                  dimension: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.photo_camera, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          key: const Key('nickname_edit'),
                          tooltip: 'Đổi nickname',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined, size: 18, color: SisoColors.body),
                          onPressed: onEditName,
                        ),
                      ],
                    ),
                    Text(profile.email,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: SisoColors.body)),
                    if (profile.campusShortCode case final code?) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          CampusDot(color: parseHexColor(profile.campusColor)),
                          const SizedBox(width: 6),
                          Text(code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Metric(value: viDecimal(profile.personalKm, 2), unit: 'km', label: 'Km cá nhân')),
              Container(width: 1, height: 36, color: SisoColors.border),
              Expanded(child: _Metric(value: '${profile.completedRuns}', label: 'Phiên chạy hoàn thành')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.unit});

  final String value;
  final String label;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text.rich(
          TextSpan(text: value, children: [
            if (unit != null)
              TextSpan(text: ' $unit', style: const TextStyle(fontSize: 12, color: SisoColors.body)),
          ]),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11.5, color: SisoColors.caption)),
      ],
    );
  }
}

/// "20/11/2026 · 16:14"
String formatRunDate(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} · ${two(t.hour)}:${two(t.minute)}';
}

/// Nhãn và màu trạng thái Phiên chạy.
(String, Color) runStatusBadge(RunSummary run) => switch (run.status) {
      'COMPLETED' => ('Hợp lệ', SisoColors.successText),
      'REJECTED' => ('Bị loại${run.rejectionReason == null ? '' : ' · ${run.rejectionReason}'}', SisoColors.danger),
      _ => ('Đang chạy', SisoColors.primary),
    };

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final RunSummary run;

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = runStatusBadge(run);
    final kind = run.sessionType == 'ARENA_LOOP' ? 'Chạy khép vòng · ${run.hexCount} ô' : 'Chạy tự do';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: SisoColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: SisoColors.border),
        ),
        child: InkWell(
          key: Key('run_${run.sessionId}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => RunDetailScreen(sessionId: run.sessionId)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatRunDate(run.startedAt),
                          style: const TextStyle(fontSize: 12, color: SisoColors.body)),
                      const SizedBox(height: 4),
                      Text('${viDecimal(run.km, 2)} km · ${formatDuration(run.durationSeconds)}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(kind, style: const TextStyle(fontSize: 12, color: SisoColors.caption)),
                    ],
                  ),
                ),
                Text(statusText,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: SisoColors.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Text('Không tải được dữ liệu.', style: TextStyle(color: SisoColors.body)),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}
