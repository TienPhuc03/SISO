import 'dart:typed_data';

/// Tác giả bài đăng / bình luận.
class ForumAuthor {
  const ForumAuthor({required this.id, required this.displayName, this.avatarUrl});

  factory ForumAuthor.fromJson(Map<String, dynamic> json) => ForumAuthor(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
      );

  final String id;
  final String displayName;

  /// Đường dẫn tương đối `/api/v1/profile/avatar/...` (cần JWT), null nếu chưa có ảnh.
  final String? avatarUrl;
}

/// Phiên chạy đính kèm bài; số liệu do server kiểm định.
class ForumRun {
  const ForumRun({required this.id, required this.distanceKm, required this.durationSeconds});

  factory ForumRun.fromJson(Map<String, dynamic> json) => ForumRun(
        id: json['id'] as String,
        distanceKm: (json['distanceKm'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toInt(),
      );

  final String id;
  final double distanceKm;
  final int durationSeconds;

  /// km/h; 0 khi chưa có thời gian.
  double get speedKmh => durationSeconds == 0 ? 0 : distanceKm / (durationSeconds / 3600);
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.body,
    required this.images,
    required this.author,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    required this.mine,
    required this.createdAt,
    this.universityShortName,
    this.universityColor,
    this.run,
    this.editedAt,
  });

  factory ForumPost.fromJson(Map<String, dynamic> json) {
    final uni = json['university'] as Map<String, dynamic>?;
    return ForumPost(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      images: [for (final u in json['images'] as List? ?? const []) u as String],
      author: ForumAuthor.fromJson(json['author'] as Map<String, dynamic>),
      universityShortName: uni?['shortName'] as String?,
      universityColor: uni?['color'] as String?,
      run: json['run'] == null ? null : ForumRun.fromJson(json['run'] as Map<String, dynamic>),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      mine: json['mine'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      editedAt: json['editedAt'] == null ? null : DateTime.parse(json['editedAt'] as String),
    );
  }

  final String id;
  final String body;

  /// URL công khai của ảnh (Supabase Storage).
  final List<String> images;
  final ForumAuthor author;
  final String? universityShortName;
  final String? universityColor;
  final ForumRun? run;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;

  /// Bài của chính mình (được sửa / xoá).
  final bool mine;
  final DateTime createdAt;

  /// Khác null = "đã chỉnh sửa".
  final DateTime? editedAt;

  ForumPost copyWith({bool? likedByMe, int? likeCount, int? commentCount}) => ForumPost(
        id: id,
        body: body,
        images: images,
        author: author,
        universityShortName: universityShortName,
        universityColor: universityColor,
        run: run,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        likedByMe: likedByMe ?? this.likedByMe,
        mine: mine,
        createdAt: createdAt,
        editedAt: editedAt,
      );
}

class ForumComment {
  const ForumComment({
    required this.id,
    required this.body,
    required this.author,
    required this.mine,
    required this.createdAt,
    this.editedAt,
  });

  factory ForumComment.fromJson(Map<String, dynamic> json) => ForumComment(
        id: json['id'] as String,
        body: json['body'] as String,
        author: ForumAuthor.fromJson(json['author'] as Map<String, dynamic>),
        mine: json['mine'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        editedAt: json['editedAt'] == null ? null : DateTime.parse(json['editedAt'] as String),
      );

  final String id;
  final String body;
  final ForumAuthor author;
  final bool mine;
  final DateTime createdAt;
  final DateTime? editedAt;
}

/// Ảnh mới chọn từ máy, chưa gửi.
class PickedImage {
  const PickedImage(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

/// Bộ lọc bảng tin.
enum ForumScope { all, cluster, university }

/// "vừa xong", "5 phút", "3 giờ", "2 ngày", rồi ngày dd/mm.
String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes} phút';
  if (d.inDays < 1) return '${d.inHours} giờ';
  if (d.inDays < 7) return '${d.inDays} ngày';
  final local = t.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
}
