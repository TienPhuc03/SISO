import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/core/network/api_client.dart';
import 'package:siso_project/src/core/storage/token_storage.dart';
import 'package:siso_project/src/features/auth/data/auth_repository.dart';

/// Giả lập server: mỗi request được trả lời bằng [handler].
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Storage hỏng: mọi thao tác đều ném lỗi (vd Android Keystore lỗi sau khi khôi phục backup).
class BrokenStorage implements TokenStorage {
  @override
  Future<String?> read(String key) => Future.error(Exception('keystore'));
  @override
  Future<void> write(String key, String value) =>
      Future.error(Exception('keystore'));
  @override
  Future<void> delete(String key) => Future.error(Exception('keystore'));
}

ResponseBody jsonBody(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// JWT không ký (chỉ dùng để đọc exp phía client).
String fakeJwt(DateTime expiry) {
  String enc(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc({
        'sub': 'u1',
        'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      })}.sig';
}

const userJson = {
  'id': 'u1',
  'email': 'sv@hutech.edu.vn',
  'displayName': 'sv',
  'university': {
    'id': 'uni-hutech',
    'shortCode': 'HUTECH',
    'name': 'ĐH Công Nghệ TP.HCM (HUTECH)',
    'color': '#FFCC00',
  },
};

void main() {
  final now = DateTime(2026, 11, 5, 8);
  late InMemoryTokenStorage storage;

  AuthRepository repoWith(ResponseBody Function(RequestOptions) handler,
      {Future<String?> Function()? googleIdToken}) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = FakeAdapter(handler);
    return AuthRepository(dio: dio, storage: storage, clock: () => now, googleIdToken: googleIdToken);
  }

  setUp(() {
    storage = InMemoryTokenStorage();
    ApiClient.setAccessToken(null);
  });

  group('isValidEmail', () {
    test('chấp nhận email bất kỳ đúng dạng', () {
      for (final email in ['a@gmail.com', ' A@UEF.EDU.VN ', 'e@st.hutech.edu.vn']) {
        expect(isValidEmail(email), isTrue, reason: email);
      }
    });

    test('từ chối chuỗi không phải email', () {
      for (final email in ['@gmail.com', 'gmail.com', 'a@b@c.com', 'a@gmail', 'a b@c.com']) {
        expect(isValidEmail(email), isFalse, reason: email);
      }
    });
  });

  group('requestOtp', () {
    test('thành công: gửi email đã chuẩn hoá, đọc BaseResponseDto', () async {
      late RequestOptions sent;
      final repo = repoWith((o) {
        sent = o;
        return jsonBody(200, {
          'success': true,
          'message': 'Mã OTP đã được gửi về hộp thư sv@hutech.edu.vn.',
          'data': {
            'email': 'sv@hutech.edu.vn',
            'expiresInSeconds': 300,
            'resendAfterSeconds': 60,
            'university': userJson['university'],
          },
        });
      });

      final result = await repo.requestOtp('  SV@Hutech.edu.vn ');

      expect(sent.path, '/api/v1/auth/email-login');
      expect(sent.data, {'email': 'sv@hutech.edu.vn'});
      expect(result.email, 'sv@hutech.edu.vn');
      expect(result.resendAfterSeconds, 60);
      expect(result.university?.shortCode, 'HUTECH');
      expect(result.sentAt, now);
      expect(result.resendWaitSeconds(now), 60);
      expect(
          result.resendWaitSeconds(now.add(const Duration(milliseconds: 59500))),
          1);
      expect(result.resendWaitSeconds(now.add(const Duration(seconds: 60))), 0);
    });

    test('lỗi nghiệp vụ backend: giữ nguyên code và message', () async {
      final repo = repoWith((_) => jsonBody(400, {
            'success': false,
            'code': 'ERR_103',
            'message': 'Vui lòng đợi 40 giây trước khi gửi lại mã OTP.',
          }));

      await expectLater(
        repo.requestOtp('sv@hutech.edu.vn'),
        throwsA(isA<SisoException>()
            .having((e) => e.code, 'code', 'ERR_103')
            .having((e) => e.message, 'message', contains('40 giây'))),
      );
    });

    test('message dạng mảng (ValidationPipe) được nối lại', () async {
      final repo = repoWith((_) => jsonBody(400, {
            'success': false,
            'code': 'HTTP_400',
            'message': ['lỗi 1', 'lỗi 2'],
          }));

      await expectLater(
        repo.requestOtp('sv@hutech.edu.vn'),
        throwsA(isA<SisoException>()
            .having((e) => e.message, 'message', 'lỗi 1\nlỗi 2')),
      );
    });

    test('không kết nối được server: ERR_NETWORK', () async {
      final repo = repoWith((o) => throw DioException.connectionError(
          requestOptions: o, reason: 'refused'));

      await expectLater(
        repo.requestOtp('sv@hutech.edu.vn'),
        throwsA(isA<SisoException>()
            .having((e) => e.code, 'code', SisoErrorCodes.network)),
      );
    });
  });

  group('email thường và Google', () {
    final token = fakeJwt(DateTime(2026, 11, 12));
    const noSchool = {'id': 'u2', 'email': 'a@gmail.com', 'displayName': 'a', 'university': null};

    test('requestOtp: gmail chưa có Trường -> university = null', () async {
      final repo = repoWith((_) => jsonBody(200, {
            'success': true,
            'message': 'ok',
            'data': {'email': 'a@gmail.com', 'expiresInSeconds': 300, 'resendAfterSeconds': 60, 'university': null},
          }));

      expect((await repo.requestOtp('a@gmail.com')).university, isNull);
    });

    test('signInWithGoogle: gửi Firebase ID token, lưu phiên như OTP', () async {
      late RequestOptions sent;
      final repo = repoWith((o) {
        sent = o;
        return jsonBody(200, {
          'success': true,
          'data': {'accessToken': token, 'user': noSchool},
        });
      }, googleIdToken: () async => 'firebase-id-token');

      final user = await repo.signInWithGoogle();

      expect(sent.path, '/api/v1/auth/google');
      expect(sent.data, {'idToken': 'firebase-id-token'});
      expect(user!.university, isNull);
      expect(storage.values[AuthRepository.tokenKey], token);
      expect(ApiClient.accessToken, token);
      expect(repo.googleAvailable, isTrue);
    });

    test('signInWithGoogle: người dùng huỷ -> null, không gọi server, không lưu gì', () async {
      var called = false;
      final repo = repoWith((_) {
        called = true;
        return jsonBody(200, {});
      }, googleIdToken: () async => null);

      expect(await repo.signInWithGoogle(), isNull);
      expect(called, isFalse);
      expect(storage.values, isEmpty);
    });

    test('server từ chối token Google -> SisoException giữ mã backend', () async {
      final repo = repoWith(
        (_) => jsonBody(401, {'success': false, 'code': 'ERR_111', 'message': 'Phiên Google không hợp lệ'}),
        googleIdToken: () async => 'bad',
      );

      await expectLater(
        repo.signInWithGoogle(),
        throwsA(isA<SisoException>().having((e) => e.code, 'code', SisoErrorCodes.googleTokenInvalid)),
      );
    });
  });

  group('verifyOtp', () {
    test('thành công: lưu JWT + user vào storage và gắn token cho ApiClient',
        () async {
      final token = fakeJwt(now.add(const Duration(days: 7)));
      final repo = repoWith((_) => jsonBody(200, {
            'success': true,
            'message': 'Đăng nhập thành công.',
            'data': {'accessToken': token, 'user': userJson},
          }));

      final user = await repo.verifyOtp('sv@hutech.edu.vn', '123456');

      expect(user.university?.shortCode, 'HUTECH');
      expect(storage.values[AuthRepository.tokenKey], token);
      expect(jsonDecode(storage.values[AuthRepository.userKey]!)['id'], 'u1');
      expect(ApiClient.accessToken, token);
    });

    test('OTP sai: ERR_102, không lưu gì', () async {
      final repo = repoWith((_) => jsonBody(400, {
            'success': false,
            'code': 'ERR_102',
            'message': 'Mã OTP không đúng. Bạn còn 4 lần thử.',
          }));

      await expectLater(
        repo.verifyOtp('sv@hutech.edu.vn', '000000'),
        throwsA(isA<SisoException>().having((e) => e.code, 'code', 'ERR_102')),
      );
      expect(storage.values, isEmpty);
      expect(ApiClient.accessToken, isNull);
    });
  });

  group('restoreSession', () {
    test('chưa có token: null, không gọi server', () async {
      var called = false;
      final repo = repoWith((_) {
        called = true;
        return jsonBody(200, {});
      });
      expect(await repo.restoreSession(), isNull);
      expect(called, isFalse);
    });

    test('token đã hết hạn: null và xoá storage, không gọi server', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.subtract(const Duration(minutes: 1)));
      var called = false;
      final repo = repoWith((_) {
        called = true;
        return jsonBody(200, {});
      });

      expect(await repo.restoreSession(), isNull);
      expect(called, isFalse);
      expect(storage.values, isEmpty);
    });

    test('token còn hạn và /me OK: trả user, gửi Bearer token', () async {
      final token = fakeJwt(now.add(const Duration(days: 3)));
      storage.values[AuthRepository.tokenKey] = token;
      late RequestOptions sent;
      final repo = repoWith((o) {
        sent = o;
        return jsonBody(200, {
          'success': true,
          'message': 'ok',
          'data': {'user': userJson},
        });
      });

      final user = await repo.restoreSession();

      expect(user?.email, 'sv@hutech.edu.vn');
      expect(sent.path, '/api/v1/auth/me');
      expect(sent.headers['Authorization'], 'Bearer $token');
      expect(ApiClient.accessToken, token);
    });

    test('/me trả token mới: lưu và dùng token đó (gia hạn phiên)', () async {
      storage.values[AuthRepository.tokenKey] = fakeJwt(now.add(const Duration(hours: 1)));
      final renewed = fakeJwt(now.add(const Duration(days: 7)));
      final repo = repoWith((_) => jsonBody(200, {
            'success': true,
            'message': 'ok',
            'data': {'user': userJson, 'accessToken': renewed},
          }));

      await repo.restoreSession();

      expect(storage.values[AuthRepository.tokenKey], renewed);
      expect(ApiClient.accessToken, renewed);
    });

    test('/me trả 401: null và xoá token', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.add(const Duration(days: 3)));
      final repo = repoWith((_) => jsonBody(401, {
            'success': false,
            'code': 'HTTP_401',
            'message': 'Unauthorized',
          }));

      expect(await repo.restoreSession(), isNull);
      expect(storage.values, isEmpty);
      expect(ApiClient.accessToken, isNull);
    });

    test('server lỗi 5xx: dùng hồ sơ đã lưu, không đăng xuất', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.add(const Duration(days: 3)));
      storage.values[AuthRepository.userKey] = jsonEncode(userJson);
      final repo = repoWith((_) => jsonBody(502, {'message': 'Bad Gateway'}));

      expect((await repo.restoreSession())?.id, 'u1');
      expect(storage.values[AuthRepository.tokenKey], isNotNull);
    });

    test('server lỗi 5xx mà chưa có hồ sơ lưu: phải đăng nhập lại', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.add(const Duration(days: 3)));
      final repo = repoWith((_) => jsonBody(500, {'message': 'x'}));

      expect(await repo.restoreSession(), isNull);
      expect(storage.values, isEmpty);
    });

    test('lỗi 4xx khác 401/403 (vd 404 do sai API_BASE_URL): giữ token, dùng hồ sơ đã lưu', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.add(const Duration(days: 3)));
      storage.values[AuthRepository.userKey] = jsonEncode(userJson);
      final repo = repoWith((_) => jsonBody(404, {'message': 'Not Found'}));

      expect((await repo.restoreSession())?.id, 'u1');
      expect(storage.values[AuthRepository.tokenKey], isNotNull);
    });

    test('/me trả 403: null và xoá token', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.add(const Duration(days: 3)));
      storage.values[AuthRepository.userKey] = jsonEncode(userJson);
      final repo = repoWith((_) => jsonBody(403, {'message': 'Forbidden'}));

      expect(await repo.restoreSession(), isNull);
      expect(storage.values, isEmpty);
    });

    test('/me trả 200 nhưng sai định dạng: null, không ném lỗi', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.add(const Duration(days: 3)));
      final repo =
          repoWith((_) => jsonBody(200, {'success': true, 'data': 'rác'}));

      expect(await repo.restoreSession(), isNull);
      expect(storage.values, isEmpty);
    });

    test('storage hỏng: null, không ném lỗi', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = FakeAdapter((_) => jsonBody(200, {}));
      final repo =
          AuthRepository(dio: dio, storage: BrokenStorage(), clock: () => now);

      expect(await repo.restoreSession(), isNull);
      expect(ApiClient.accessToken, isNull);
    });

    test('mất mạng: dùng hồ sơ đã lưu nếu token còn hạn', () async {
      storage.values[AuthRepository.tokenKey] =
          fakeJwt(now.add(const Duration(days: 3)));
      storage.values[AuthRepository.userKey] = jsonEncode(userJson);
      final repo = repoWith((o) => throw DioException.connectionError(
          requestOptions: o, reason: 'offline'));

      final user = await repo.restoreSession();

      expect(user?.id, 'u1');
      expect(storage.values, isNotEmpty);
    });
  });

  test('logout xoá storage và token của ApiClient', () async {
    storage.values[AuthRepository.tokenKey] = 't';
    storage.values[AuthRepository.userKey] = '{}';
    ApiClient.setAccessToken('t');

    await repoWith((_) => jsonBody(200, {})).logout();

    expect(storage.values, isEmpty);
    expect(ApiClient.accessToken, isNull);
  });

  test('jwtExpiry đọc exp, token rác trả null', () {
    final exp = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000);
    expect(jwtExpiry(fakeJwt(exp)), exp);
    expect(jwtExpiry('abc'), isNull);
    expect(jwtExpiry('a.b.c'), isNull);
  });
}
