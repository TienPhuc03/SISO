import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../../../core/theme/siso_theme.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/providers/profile_providers.dart';
import '../domain/forum_models.dart';
import '../providers/forum_providers.dart';

const maxPostImages = 4;
const maxPostImageBytes = 1024 * 1024;

/// Đăng bài mới, hoặc sửa bài của mình ([post] khác null). Pop trả về bài đã lưu.
class PostEditorScreen extends ConsumerStatefulWidget {
  const PostEditorScreen({super.key, this.post, this.imagePicker});

  final ForumPost? post;

  /// Test truyền bộ chọn ảnh giả.
  final ImagePicker? imagePicker;

  @override
  ConsumerState<PostEditorScreen> createState() => _PostEditorScreenState();
}

class _PostEditorScreenState extends ConsumerState<PostEditorScreen> {
  late final _body = TextEditingController(text: widget.post?.body ?? '');
  late final List<String> _kept = [...?widget.post?.images];
  final List<PickedImage> _added = [];
  late String? _sessionId = widget.post?.run?.id;
  bool _saving = false;

  bool get _editing => widget.post != null;
  int get _imageCount => _kept.length + _added.length;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickImages() async {
    final remaining = maxPostImages - _imageCount;
    if (remaining <= 0) return _toast('Tối đa $maxPostImages ảnh mỗi bài.');
    // Thu nhỏ ngay trên máy để ảnh dưới trần 1 MB của server.
    final files = await (widget.imagePicker ?? ImagePicker())
        .pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 80, limit: remaining);
    var tooBig = 0;
    for (final f in files.take(remaining)) {
      final bytes = await f.readAsBytes();
      if (bytes.length > maxPostImageBytes) {
        tooBig++;
        continue;
      }
      _added.add(PickedImage(bytes, f.name));
    }
    if (mounted) setState(() {});
    if (tooBig > 0) _toast('Bỏ qua $tooBig ảnh lớn hơn 1 MB.');
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty && _imageCount == 0) return _toast('Viết gì đó hoặc thêm ít nhất một ảnh.');
    setState(() => _saving = true);
    try {
      final repo = ref.read(forumRepositoryProvider);
      final saved = _editing
          ? await repo.updatePost(widget.post!.id,
              body: body, sessionId: _sessionId ?? '', keepImages: _kept, newImages: _added)
          : await repo.createPost(body: body, sessionId: _sessionId, images: _added);
      if (mounted) Navigator.of(context).pop(saved);
    } on SisoException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Không kết nối được máy chủ. Thử lại sau.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickRun() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (_) => const _RunPickerSheet(),
    );
    if (picked != null && mounted) setState(() => _sessionId = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Sửa bài' : 'Đăng bài'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('post_save'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_editing ? 'Lưu' : 'Đăng'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('post_body'),
            controller: _body,
            maxLength: 2000,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Khoe thành tích hôm nay của bạn…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in _kept)
                _Thumb(
                  key: Key('thumb_$url'),
                  image: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: SisoColors.track,
                      child: Icon(Icons.broken_image_outlined, color: SisoColors.caption),
                    ),
                  ),
                  onRemove: () => setState(() => _kept.remove(url)),
                ),
              for (final img in _added)
                _Thumb(
                  image: Image.memory(img.bytes, fit: BoxFit.cover),
                  onRemove: () => setState(() => _added.remove(img)),
                ),
              if (_imageCount < maxPostImages)
                InkWell(
                  key: const Key('post_add_image'),
                  onTap: _saving ? null : _pickImages,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      border: Border.all(color: SisoColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Icon(Icons.add_photo_alternate_outlined), Text('Ảnh', style: TextStyle(fontSize: 12))],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Tối đa $maxPostImages ảnh, mỗi ảnh ≤ 1 MB.',
              style: TextStyle(fontSize: 12, color: SisoColors.caption)),
          const SizedBox(height: 16),
          ListTile(
            key: const Key('post_attach_run'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.directions_run, color: SisoColors.primary),
            title: Text(_sessionId == null ? 'Đính kèm Phiên chạy' : 'Đã đính kèm Phiên chạy'),
            subtitle: const Text('Km, thời gian và pace do máy chủ xác thực.'),
            trailing: _sessionId == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: 'Bỏ đính kèm',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _sessionId = null),
                  ),
            onTap: _pickRun,
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({super.key, required this.image, required this.onRemove});

  final Widget image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 84,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 16, color: Colors.white, semanticLabel: 'Bỏ ảnh'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chọn một Phiên chạy hợp lệ (đã hoàn thành) trong Lịch sử Phiên chạy.
class _RunPickerSheet extends ConsumerWidget {
  const _RunPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(runHistoryProvider);
    return SafeArea(
      child: runs.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (_, __) => const Padding(padding: EdgeInsets.all(24), child: Text('Không tải được Lịch sử Phiên chạy.')),
        data: (list) {
          final valid = list.where((r) => r.status == 'COMPLETED').toList();
          if (valid.isEmpty) {
            return const Padding(
                padding: EdgeInsets.all(24), child: Text('Chưa có Phiên chạy hợp lệ nào để đính kèm.'));
          }
          return ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Chọn Phiên chạy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final RunSummary r in valid)
                ListTile(
                  key: Key('pick_run_${r.sessionId}'),
                  leading: const Icon(Icons.directions_run),
                  title: Text('${viDecimal(r.km, 2)} km'),
                  subtitle: Text(_date(r.startedAt)),
                  onTap: () => Navigator.of(context).pop(r.sessionId),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _date(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
