import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../../../core/theme/siso_theme.dart';
import '../../auth/data/auth_repository.dart' show unexpectedAuthError;
import '../../auth/presentation/logout_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../../leaderboard/presentation/leaderboard_screen.dart';
import '../../map/domain/hex_cell.dart' show parseHexColor;
import '../domain/university_catalog.dart';
import '../providers/university_providers.dart';

/// Chọn Trường để cống hiến: tìm không dấu trong danh mục, không thấy thì thêm Trường mới (tính điểm ngay).
/// Mở từ AuthGate (tài khoản chưa có Trường) hoặc push từ hộp thoại đầu Mùa / Hồ sơ để đổi Trường.
class UniversityPickerScreen extends ConsumerStatefulWidget {
  const UniversityPickerScreen({super.key});

  @override
  ConsumerState<UniversityPickerScreen> createState() => _UniversityPickerScreenState();
}

class _UniversityPickerScreenState extends ConsumerState<UniversityPickerScreen> {
  final _search = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int? get _season {
    final s = ref.read(authSessionProvider);
    return s is AuthSignedIn ? s.user.seasonNumber : null;
  }

  Future<void> _submit(String label, String clusterName, Future<void> Function() call) async {
    final season = _season;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowDirection: VerticalDirection.up,
        title: Text('Cống hiến cho $label?'),
        content: Text(
          '$clusterName.\n\nBạn sẽ chạy cho Trường này đến hết ${season == null ? 'Mùa giải' : 'Mùa $season'}; '
          'chỉ đổi được khi Mùa sau bắt đầu và trước Phiên chạy đầu tiên của Mùa đó.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Chọn lại')),
          FilledButton(
            key: const Key('uni_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await call();
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on SisoException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast(unexpectedAuthError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choose(UniversityCatalog catalog, UniversityOption u) => _submit(
        u.shortName,
        catalog.clusterName(u.clusterCode),
        () async {
          final user = await ref.read(authRepositoryProvider).chooseUniversity(universityId: u.id);
          ref.read(authSessionProvider.notifier).signedIn(user);
        },
      );

  Future<void> _addNew(UniversityCatalog catalog) async {
    final draft = await showModalBottomSheet<_NewUniversity>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddUniversitySheet(catalog: catalog, initialName: _search.text.trim()),
    );
    if (draft == null || !mounted) return;
    await _submit(draft.shortName, catalog.clusterName(catalog.clusterOfDistrict(draft.district)), () async {
      final user = await ref.read(authRepositoryProvider).chooseUniversity(
            name: draft.name,
            shortName: draft.shortName,
            district: draft.district,
          );
      ref.invalidate(universityCatalogProvider);
      ref.read(authSessionProvider.notifier).signedIn(user);
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(universityCatalogProvider);
    final session = ref.watch(authSessionProvider);
    final firstTime = session is AuthSignedIn && session.user.university == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn Trường của bạn', key: Key('uni_picker')),
        actions: [
          if (firstTime) ...[
            IconButton(
              tooltip: 'Xem bảng xếp hạng',
              icon: const Icon(Icons.leaderboard_outlined),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LeaderboardScreen())),
            ),
            const Padding(padding: EdgeInsets.only(right: 12), child: LogoutButton()),
          ],
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Không tải được danh sách Trường.', key: Key('uni_error')),
                TextButton(onPressed: () => ref.invalidate(universityCatalogProvider), child: const Text('Thử lại')),
              ],
            ),
          ),
          data: (data) => _buildList(data),
        ),
      ),
    );
  }

  Widget _buildList(UniversityCatalog catalog) {
    final hits = searchUniversities(catalog.universities, _search.text);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const Key('uni_search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tìm tên trường, viết tắt hoặc quận (vd. kinh te, UEH)',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: SisoColors.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_saving) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final u in hits)
                ListTile(
                  key: Key('uni_${u.id}'),
                  leading: CampusDot(color: parseHexColor(u.color), size: 14),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(u.shortName,
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (!u.verified) ...[
                        const SizedBox(width: 6),
                        const Text('Chờ duyệt', style: TextStyle(fontSize: 11, color: SisoColors.warningText)),
                      ],
                    ],
                  ),
                  subtitle: Text('${u.name}\n${u.district ?? ''} · ${catalog.clusterName(u.clusterCode)}',
                      style: const TextStyle(fontSize: 12.5, color: SisoColors.body)),
                  isThreeLine: true,
                  onTap: () => _choose(catalog, u),
                ),
              if (hits.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Không tìm thấy Trường nào khớp.', style: TextStyle(color: SisoColors.body)),
                ),
              const Divider(),
              ListTile(
                key: const Key('uni_add'),
                leading: const Icon(Icons.add_circle_outline, color: SisoColors.primary),
                title: const Text('Không thấy Trường của bạn? Thêm Trường mới'),
                subtitle: const Text('Trường mới được tính điểm ngay; admin sẽ kiểm tra lại tên.'),
                onTap: () => _addNew(catalog),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NewUniversity {
  const _NewUniversity(this.name, this.shortName, this.district);
  final String name;
  final String shortName;
  final String district;
}

/// Form thêm Trường: tên đầy đủ, tên viết tắt, quận (hiện Cụm tương ứng).
class _AddUniversitySheet extends StatefulWidget {
  const _AddUniversitySheet({required this.catalog, required this.initialName});

  final UniversityCatalog catalog;
  final String initialName;

  @override
  State<_AddUniversitySheet> createState() => _AddUniversitySheetState();
}

class _AddUniversitySheetState extends State<_AddUniversitySheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _short = TextEditingController();
  String? _district;

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cluster = _district == null ? null : widget.catalog.clusterName(widget.catalog.clusterOfDistrict(_district!));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Thêm Trường mới', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Trường có nhiều cơ sở thì ghi rõ cơ sở bạn học, vd. "ĐH Kinh tế TP.HCM (UEH) - Cơ sở V".',
                style: TextStyle(fontSize: 12.5, color: SisoColors.body)),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('new_uni_name'),
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Tên trường đầy đủ (kèm cơ sở)'),
              validator: (v) => (v ?? '').trim().length < 5 ? 'Tối thiểu 5 ký tự' : null,
            ),
            TextFormField(
              key: const Key('new_uni_short'),
              controller: _short,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Tên viết tắt (vd. UEH V)'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Tối thiểu 2 ký tự' : null,
            ),
            DropdownButtonFormField<String>(
              key: const Key('new_uni_district'),
              initialValue: _district,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Quận nơi cơ sở toạ lạc', helperText: cluster),
              items: [
                for (final d in widget.catalog.districts) DropdownMenuItem(value: d.name, child: Text(d.name)),
              ],
              onChanged: (v) => setState(() => _district = v),
              validator: (v) => v == null ? 'Chọn quận' : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('new_uni_submit'),
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.of(context).pop(_NewUniversity(_name.text.trim(), _short.text.trim(), _district!));
              },
              child: const Text('Tiếp tục'),
            ),
          ],
        ),
      ),
    );
  }
}
