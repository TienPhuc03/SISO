import 'package:flutter/material.dart';

import '../../../core/errors/siso_exceptions.dart';

/// Báo lỗi gọn: lỗi nghiệp vụ hiện đúng message server, còn lại báo mất kết nối.
void showForumError(BuildContext context, Object error) {
  final text = error is SisoException ? error.message : 'Không kết nối được máy chủ. Thử lại sau.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirmForumDelete(BuildContext context, String what) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowDirection: VerticalDirection.up,
        title: Text('Xoá $what?'),
        content: Text(what == 'bài'
            ? 'Bài bị xoá hẳn cùng ảnh, tym và bình luận. Không hoàn tác được.'
            : 'Bình luận bị xoá hẳn. Không hoàn tác được.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Huỷ')),
          FilledButton(
            key: const Key('forum_delete_confirm'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    ) ==
    true;

/// Hỏi lý do báo cáo (tuỳ chọn). null = huỷ.
Future<String?> askReportReason(BuildContext context, String what) => showDialog<String>(
      context: context,
      builder: (_) => _ReportDialog(what: what),
    );

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.what});
  final String what;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowDirection: VerticalDirection.up,
        title: Text('Báo cáo ${widget.what}'),
        content: TextField(
          key: const Key('report_reason'),
          controller: _reason,
          maxLength: 300,
          decoration: const InputDecoration(hintText: 'Lý do (không bắt buộc): spam, xúc phạm, ảnh không phù hợp…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
          FilledButton(
            key: const Key('report_send'),
            onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
            child: const Text('Gửi báo cáo'),
          ),
        ],
      );
}

/// Hộp thoại sửa bình luận; null = huỷ.
Future<String?> editCommentDialog(BuildContext context, String initial) => showDialog<String>(
      context: context,
      builder: (_) => _EditCommentDialog(initial: initial),
    );

class _EditCommentDialog extends StatefulWidget {
  const _EditCommentDialog({required this.initial});
  final String initial;

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowDirection: VerticalDirection.up,
        title: const Text('Sửa bình luận'),
        content:
            TextField(key: const Key('comment_edit'), controller: _text, maxLength: 1000, maxLines: 4, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
          FilledButton(
            key: const Key('comment_edit_save'),
            onPressed: () => Navigator.of(context).pop(_text.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      );
}
