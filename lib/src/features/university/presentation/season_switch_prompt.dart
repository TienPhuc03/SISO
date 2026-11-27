import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/token_storage.dart';
import '../../auth/providers/auth_provider.dart';
import 'university_picker_screen.dart';

/// Lưu Mùa giải đã hỏi "Ở lại hay đổi Trường?" để mỗi Mùa chỉ hỏi một lần trên máy này.
final seasonPromptStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());

const seasonPromptKey = 'siso_season_prompt';

/// Đầu Mùa mới (server báo còn đổi được Trường): hỏi một lần "Ở lại X hay cống hiến cho Trường khác?".
/// Không trả lời = ở lại; đổi được cho tới Phiên chạy hợp lệ đầu tiên của Mùa.
class SeasonSwitchPrompt extends ConsumerStatefulWidget {
  const SeasonSwitchPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SeasonSwitchPrompt> createState() => _SeasonSwitchPromptState();
}

class _SeasonSwitchPromptState extends ConsumerState<SeasonSwitchPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    final session = ref.read(authSessionProvider);
    if (session is! AuthSignedIn) return;
    final user = session.user;
    final campus = user.university;
    final season = user.seasonNumber;
    if (campus == null || !user.canChangeUniversity || season == null) return;

    final storage = ref.read(seasonPromptStorageProvider);
    try {
      if (await storage.read(seasonPromptKey) == '$season') return;
      await storage.write(seasonPromptKey, '$season');
    } catch (_) {
      return; // storage hỏng: thà không hỏi còn hơn hỏi mỗi lần mở app
    }
    if (!mounted) return;

    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.flag_outlined),
        title: Text('Mùa $season đã bắt đầu'),
        content: Text(
          'Bạn đang cống hiến cho ${campus.shortName}. Ở lại hay chuyển sang Trường khác?\n\n'
          'Bạn đổi được cho tới Phiên chạy hợp lệ đầu tiên của Mùa này.',
        ),
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowDirection: VerticalDirection.up,
        actions: [
          TextButton(
            key: const Key('season_switch'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đổi Trường'),
          ),
          FilledButton(
            key: const Key('season_stay'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Ở lại ${campus.shortName}'),
          ),
        ],
      ),
    );
    if (change == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UniversityPickerScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
