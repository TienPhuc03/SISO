import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:siso_project/src/core/network/api_client.dart';

import '../../auth/data/auth_repository.dart' show mapAuthError;
import '../domain/forum_models.dart';

/// Diễn đàn (`/api/v1/forum/*`). Lỗi được đổi thành SisoException (giữ mã ERR_xxx của backend).
class ForumRepository {
  Future<T> _call<T>(Future<Response<dynamic>> Function() send, T Function(dynamic data) read) async {
    try {
      final body = (await send()).data as Map<String, dynamic>;
      return read(body['data']);
    } on DioException catch (e) {
      throw mapAuthError(e);
    }
  }

  static final _multipart = Options(contentType: 'multipart/form-data');

  Future<List<ForumPost>> feed({String? cluster, String? universityId, DateTime? before, int limit = 20}) => _call(
        () => ApiClient.dio.get('/api/v1/forum/posts', queryParameters: {
          if (cluster != null) 'cluster': cluster,
          if (universityId != null) 'universityId': universityId,
          if (before != null) 'before': before.toUtc().toIso8601String(),
          'limit': limit,
        }),
        (d) => [for (final p in d as List) ForumPost.fromJson(p as Map<String, dynamic>)],
      );

  Future<ForumPost> getPost(String id) =>
      _call(() => ApiClient.dio.get('/api/v1/forum/posts/$id'), (d) => ForumPost.fromJson(d as Map<String, dynamic>));

  Future<ForumPost> createPost({required String body, String? sessionId, List<PickedImage> images = const []}) => _call(
        () => ApiClient.dio.post(
          '/api/v1/forum/posts',
          data: FormData.fromMap({
            'body': body,
            if (sessionId != null) 'sessionId': sessionId,
            'images': [for (final i in images) MultipartFile.fromBytes(i.bytes, filename: i.filename)],
          }),
          options: _multipart,
        ),
        (d) => ForumPost.fromJson(d as Map<String, dynamic>),
      );

  /// [sessionId] = '' để bỏ Phiên chạy đính kèm; [keepImages] là URL ảnh cũ giữ lại (theo thứ tự).
  Future<ForumPost> updatePost(
    String id, {
    required String body,
    required String sessionId,
    required List<String> keepImages,
    List<PickedImage> newImages = const [],
  }) =>
      _call(
        () => ApiClient.dio.patch(
          '/api/v1/forum/posts/$id',
          data: FormData.fromMap({
            'body': body,
            'sessionId': sessionId,
            'keepImages': jsonEncode(keepImages),
            'images': [for (final i in newImages) MultipartFile.fromBytes(i.bytes, filename: i.filename)],
          }),
          options: _multipart,
        ),
        (d) => ForumPost.fromJson(d as Map<String, dynamic>),
      );

  Future<void> deletePost(String id) => _call(() => ApiClient.dio.delete('/api/v1/forum/posts/$id'), (_) {});

  /// Trả số tym mới.
  Future<int> setLiked(String id, bool liked) => _call(
        () => liked
            ? ApiClient.dio.put('/api/v1/forum/posts/$id/like')
            : ApiClient.dio.delete('/api/v1/forum/posts/$id/like'),
        (d) => ((d as Map)['likeCount'] as num).toInt(),
      );

  Future<List<ForumComment>> comments(String postId) => _call(
        () => ApiClient.dio.get('/api/v1/forum/posts/$postId/comments'),
        (d) => [for (final c in d as List) ForumComment.fromJson(c as Map<String, dynamic>)],
      );

  Future<ForumComment> addComment(String postId, String body) => _call(
        () => ApiClient.dio.post('/api/v1/forum/posts/$postId/comments', data: {'body': body}),
        (d) => ForumComment.fromJson(d as Map<String, dynamic>),
      );

  Future<ForumComment> updateComment(String id, String body) => _call(
        () => ApiClient.dio.patch('/api/v1/forum/comments/$id', data: {'body': body}),
        (d) => ForumComment.fromJson(d as Map<String, dynamic>),
      );

  Future<void> deleteComment(String id) => _call(() => ApiClient.dio.delete('/api/v1/forum/comments/$id'), (_) {});

  Future<void> report(String postId, {String? commentId, String? reason}) => _call(
        () => ApiClient.dio.post('/api/v1/forum/posts/$postId/report', data: {
          if (commentId != null) 'commentId': commentId,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        }),
        (_) {},
      );
}
