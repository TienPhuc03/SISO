import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Nơi lưu JWT và hồ sơ user đã đăng nhập (để mở lại app không phải đăng nhập lại).
abstract class TokenStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Lưu vào Keychain (iOS) / Keystore (Android) / WebCrypto (web)
/// qua `flutter_secure_storage`.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Bản lưu trong RAM, dùng cho test.
class InMemoryTokenStorage implements TokenStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
