import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/network/api_client.dart';

/// Mọi request đều nhận 401; [whileInFlight] chạy lúc request đã gửi đi mà chưa có phản hồi.
class Always401 implements HttpClientAdapter {
  void Function()? whileInFlight;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    whileInFlight?.call();
    return ResponseBody.fromString('{}', 401, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  var unauthorized = 0;
  final adapter = Always401();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://test');
    ApiClient.initialize();
    ApiClient.dio.httpClientAdapter = adapter;
    ApiClient.onUnauthorized = () => unauthorized++;
  });

  setUp(() {
    unauthorized = 0;
    adapter.whileInFlight = null;
  });

  Future<void> get() async {
    try {
      await ApiClient.dio.get('/x');
    } on DioException catch (_) {}
  }

  test('401 cho token hiện tại: đăng xuất', () async {
    ApiClient.setAccessToken('moi');
    await get();
    expect(unauthorized, 1);
  });

  test('401 về muộn của token cũ (đã đăng nhập lại): không đá phiên mới', () async {
    ApiClient.setAccessToken('cu');
    adapter.whileInFlight = () => ApiClient.setAccessToken('moi');
    await get();
    expect(unauthorized, 0);
  });

  test('401 khi chưa đăng nhập (request không có token): không gọi đăng xuất', () async {
    ApiClient.setAccessToken(null);
    await get();
    expect(unauthorized, 0);
  });
}
