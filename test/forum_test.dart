import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';
import 'package:siso_project/src/features/forum/data/forum_repository.dart';
import 'package:siso_project/src/features/forum/domain/forum_models.dart';
import 'package:siso_project/src/features/forum/presentation/forum_screen.dart';
import 'package:siso_project/src/features/forum/presentation/post_detail_screen.dart';
import 'package:siso_project/src/features/forum/presentation/post_editor_screen.dart';
import 'package:siso_project/src/features/forum/providers/forum_providers.dart';
import 'package:siso_project/src/features/profile/data/profile_repository.dart';
import 'package:siso_project/src/features/profile/domain/profile_models.dart';
import 'package:siso_project/src/features/profile/providers/profile_providers.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, student;

ForumPost post(String id, {bool mine = false, bool liked = false, int likes = 2, int comments = 0, List<String> images = const []}) =>
    ForumPost.fromJson({
      'id': id,
      'body': 'Bài $id',
      'images': images,
      'author': {'id': mine ? 'u1' : 'u2', 'displayName': mine ? 'Tôi' : 'Bạn khác', 'avatarUrl': null},
      'university': {'id': 'uni-hutech', 'shortName': 'HUTECH', 'color': '#FFCC00', 'clusterCode': 'NORTH'},
      'run': {'id': 's1', 'distanceKm': 5.23, 'durationSeconds': 1800},
      'likeCount': likes,
      'commentCount': comments,
      'likedByMe': liked,
      'mine': mine,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
      'editedAt': null,
    });

class FakeForumRepository extends ForumRepository {
  List<ForumPost> posts = [];
  final feedCalls = <Map<String, String?>>[];
  final calls = <String>[];
  Object? likeError;
  Map<String, Object?>? created;
  Map<String, Object?>? updated;
  List<ForumComment> commentList = [];

  @override
  Future<List<ForumPost>> feed({String? cluster, String? universityId, DateTime? before, int limit = 20}) async {
    feedCalls.add({'cluster': cluster, 'universityId': universityId});
    return posts;
  }

  @override
  Future<ForumPost> getPost(String id) async => posts.firstWhere((p) => p.id == id);

  @override
  Future<int> setLiked(String id, bool liked) async {
    calls.add('like:$id:$liked');
    if (likeError != null) throw likeError!;
    return 10;
  }

  @override
  Future<void> deletePost(String id) async => calls.add('delete:$id');

  @override
  Future<void> report(String postId, {String? commentId, String? reason}) async =>
      calls.add('report:$postId:${commentId ?? ''}:$reason');

  @override
  Future<ForumPost> createPost({required String body, String? sessionId, List<PickedImage> images = const []}) async {
    created = {'body': body, 'sessionId': sessionId, 'images': images.length};
    return post('new', mine: true);
  }

  @override
  Future<ForumPost> updatePost(String id,
      {required String body, required String sessionId, required List<String> keepImages, List<PickedImage> newImages = const []}) async {
    updated = {'body': body, 'sessionId': sessionId, 'keep': keepImages};
    return post(id, mine: true);
  }

  @override
  Future<List<ForumComment>> comments(String postId) async => commentList;

  @override
  Future<ForumComment> addComment(String postId, String body) async {
    calls.add('comment:$postId:$body');
    final c = ForumComment.fromJson({
      'id': 'c${commentList.length + 1}',
      'body': body,
      'author': {'id': 'u1', 'displayName': 'Tôi'},
      'mine': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    commentList = [...commentList, c];
    return c;
  }
}

class FakeProfileRepository extends ProfileRepository {
  @override
  Future<List<RunSummary>> fetchRuns({int limit = 50}) async => [
        RunSummary.fromJson({
          'sessionId': 's-ok',
          'status': 'COMPLETED',
          'sessionType': 'FREE_RUN',
          'distanceMeters': 4200,
          'durationSeconds': 1500,
          'hexCount': 0,
          'startedAt': '2026-11-26T23:00:00.000Z',
        }),
        RunSummary.fromJson({
          'sessionId': 's-bad',
          'status': 'REJECTED',
          'sessionType': 'FREE_RUN',
          'distanceMeters': 9000,
          'durationSeconds': 600,
          'hexCount': 0,
          'startedAt': '2026-11-25T23:00:00.000Z',
        }),
      ];
}

const noSchool = AuthUser(id: 'u9', email: 'a@gmail.com', displayName: 'a', university: null);

void main() {
  late FakeForumRepository repo;

  Future<void> pump(WidgetTester tester, Widget home, {AuthUser user = student}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        forumRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()..restoredUser = user),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
      ],
      child: MaterialApp(home: home),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => repo = FakeForumRepository());

  group('Mô hình', () {
    test('timeAgo', () {
      final now = DateTime(2026, 11, 27, 12);
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'vừa xong');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5 phút');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now), '3 giờ');
      expect(timeAgo(now.subtract(const Duration(days: 2)), now), '2 ngày');
      expect(timeAgo(DateTime(2026, 11, 1, 12), now), '01/11');
    });

    test('đọc bài từ API, pace từ Phiên chạy', () {
      final p = post('p1');
      expect(p.run!.distanceKm, 5.23);
      expect(p.run!.speedKmh, closeTo(10.46, 0.01));
      expect(p.universityShortName, 'HUTECH');
    });
  });

  group('Bảng tin', () {
    testWidgets('hiện bài, Phiên chạy đã xác thực; tym cập nhật ngay rồi lấy số từ server', (tester) async {
      repo.posts = [post('p1')];
      await pump(tester, const ForumScreen());

      expect(find.text('Bài p1'), findsOneWidget);
      expect(find.textContaining('5,23 km'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('post_like_p1')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['like:p1:true']);
      expect(find.text('10'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('tym lỗi: trả lại như cũ và báo lỗi', (tester) async {
      repo
        ..posts = [post('p1')]
        ..likeError = const SisoException(code: 'ERR_109', message: 'Bạn cần chọn Trường trước khi chạy.');
      await pump(tester, const ForumScreen());

      await tester.tap(find.byKey(const Key('post_like_p1')));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Bạn cần chọn Trường trước khi chạy.'), findsOneWidget);
    });

    testWidgets('lọc Cụm / Trường của tôi gửi đúng tham số', (tester) async {
      await pump(tester, const ForumScreen());
      await tester.tap(find.byKey(const Key('forum_scope_cluster')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum_scope_university')));
      await tester.pumpAndSettle();

      expect(repo.feedCalls.sublist(repo.feedCalls.length - 2), [
        {'cluster': 'NORTH', 'universityId': null},
        {'cluster': null, 'universityId': 'uni-hutech'},
      ]);
    });

    testWidgets('bài của mình: Sửa / Xoá; xoá sau khi xác nhận thì biến khỏi bảng tin', (tester) async {
      repo.posts = [post('p1', mine: true)];
      await pump(tester, const ForumScreen());

      await tester.tap(find.byKey(const Key('post_menu_p1')));
      await tester.pumpAndSettle();
      expect(find.text('Sửa bài'), findsOneWidget);
      expect(find.text('Báo cáo bài'), findsNothing);
      await tester.tap(find.text('Xoá bài'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum_delete_confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['delete:p1']);
      expect(find.text('Bài p1'), findsNothing);
    });

    testWidgets('bài người khác: chỉ Báo cáo, gửi kèm lý do', (tester) async {
      repo.posts = [post('p1')];
      await pump(tester, const ForumScreen());

      await tester.tap(find.byKey(const Key('post_menu_p1')));
      await tester.pumpAndSettle();
      expect(find.text('Xoá bài'), findsNothing);
      await tester.tap(find.text('Báo cáo bài'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('report_reason')), 'spam');
      await tester.tap(find.byKey(const Key('report_send')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['report:p1::spam']);
      expect(find.text('Đã gửi báo cáo cho admin.'), findsOneWidget);
    });

    testWidgets('chưa chọn Trường: xem được, không đăng / tym được', (tester) async {
      repo.posts = [post('p1')];
      await pump(tester, const ForumScreen(), user: noSchool);

      expect(find.text('Bài p1'), findsOneWidget);
      expect(find.byKey(const Key('forum_new_post')), findsNothing);
      expect(tester.widget<TextButton>(find.byKey(const Key('post_like_p1'))).onPressed, isNull);
    });
  });

  group('Đăng / sửa bài', () {
    testWidgets('bài rỗng: báo, không gửi', (tester) async {
      await pump(tester, const PostEditorScreen());
      await tester.tap(find.byKey(const Key('post_save')));
      await tester.pumpAndSettle();
      expect(find.text('Viết gì đó hoặc thêm ít nhất một ảnh.'), findsOneWidget);
      expect(repo.created, isNull);
    });

    testWidgets('đính kèm Phiên chạy: chỉ liệt kê Phiên hợp lệ; gửi kèm sessionId', (tester) async {
      await pump(tester, const PostEditorScreen());
      await tester.enterText(find.byKey(const Key('post_body')), 'Sáng nay 4 km');
      await tester.tap(find.byKey(const Key('post_attach_run')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pick_run_s-bad')), findsNothing);
      await tester.tap(find.byKey(const Key('pick_run_s-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('post_save')));
      await tester.pumpAndSettle();

      expect(repo.created, {'body': 'Sáng nay 4 km', 'sessionId': 's-ok', 'images': 0});
    });

    testWidgets('sửa: bỏ một ảnh cũ, bỏ Phiên chạy -> gửi ảnh giữ lại và sessionId rỗng', (tester) async {
      final p = post('p1', mine: true, images: ['https://x/a.jpg', 'https://x/b.jpg']);
      await pump(tester, PostEditorScreen(post: p));

      await tester.tap(find.descendant(of: find.byKey(const Key('thumb_https://x/a.jpg')), matching: find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bỏ đính kèm'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('post_save')));
      await tester.pumpAndSettle();

      expect(repo.updated, {'body': 'Bài p1', 'sessionId': '', 'keep': ['https://x/b.jpg']});
    });
  });

  group('Chi tiết bài', () {
    testWidgets('gửi bình luận: thêm vào danh sách, tăng số bình luận', (tester) async {
      repo.posts = [post('p1', comments: 0)];
      await pump(tester, const PostDetailScreen(postId: 'p1'));
      expect(find.text('Chưa có bình luận.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('comment_input')), 'Đỉnh quá!');
      await tester.tap(find.byKey(const Key('comment_send')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['comment:p1:Đỉnh quá!']);
      expect(find.text('Đỉnh quá!'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });
}
