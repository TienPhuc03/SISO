import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Quản lý cấu hình môi trường & hằng số toàn hệ thống
class AppConstants {
  AppConstants._();

  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';
  static String get socketUrl =>
      dotenv.env['SOCKET_URL'] ?? 'http://localhost:3000/turf-ws';
  static int get h3Resolution =>
      int.tryParse(dotenv.env['H3_RESOLUTION'] ?? '10') ?? 10;
  static String get campusBoundary =>
      dotenv.env['CAMPUS_BOUNDARY'] ?? 'BINH_THANH';

  /// Danh sách email domain hợp lệ của 5 trường Bình Thạnh
  static const List<String> allowedCampusDomains = [
    'hutech.edu.vn',
    'uef.edu.vn',
    'ut.edu.vn',
    'ftu.edu.vn',
    'hiu.vn',
  ];
}
