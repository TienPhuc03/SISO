/// Trường của Sinh viên (khớp `university` trong response Auth).
class CampusInfo {
  const CampusInfo({
    required this.id,
    required this.shortCode,
    required this.name,
    required this.color,
    String? shortName,
    this.clusterCode,
  }) : shortName = shortName ?? shortCode;

  final String id;
  final String shortCode;

  /// Tên ngắn hiển thị (vd. "UEH Cơ sở N"); server không gửi thì dùng [shortCode].
  final String shortName;
  final String name;

  /// Cụm của Trường (THU_DUC, CENTRAL, NORTH, SOUTH); null nếu chưa rõ.
  final String? clusterCode;

  /// Mã màu dạng `#RRGGBB`
  final String color;

  factory CampusInfo.fromJson(Map<String, dynamic> json) => CampusInfo(
        id: json['id'] as String,
        shortCode: json['shortCode'] as String,
        name: json['name'] as String,
        color: json['color'] as String,
        shortName: json['shortName'] as String?,
        clusterCode: json['clusterCode'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'shortCode': shortCode,
        'shortName': shortName,
        'name': name,
        'color': color,
        'clusterCode': clusterCode,
      };
}

/// Sinh viên đã đăng nhập.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.university,
    this.role = 'user',
    this.canChangeUniversity = false,
    this.seasonNumber,
  });

  final String id;
  final String email;
  final String displayName;
  /// null = chưa chọn Trường (tài khoản mới).
  final CampusInfo? university;

  /// 'admin' thì không cần chọn Trường.
  final String role;

  /// Được chọn / đổi Trường ngay lúc này (luật khoá theo Mùa giải, server tính).
  final bool canChangeUniversity;

  /// Mùa giải đang mở lúc server trả hồ sơ.
  final int? seasonNumber;

  bool get isAdmin => role == 'admin';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: (json['displayName'] as String?) ?? '',
        university: switch (json['university']) {
          Map<String, dynamic> u => CampusInfo.fromJson(u),
          _ => null,
        },
        role: json['role'] as String? ?? 'user',
        canChangeUniversity: json['canChangeUniversity'] as bool? ?? false,
        seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'university': university?.toJson(),
        'role': role,
        'canChangeUniversity': canChangeUniversity,
        'seasonNumber': seasonNumber,
      };
}

/// Kết quả bước gửi OTP.
class OtpRequestResult {
  const OtpRequestResult({
    required this.email,
    required this.message,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
    required this.university,
    required this.sentAt,
  });

  final String email;
  final String message;
  final int expiresInSeconds;
  final int resendAfterSeconds;

  /// Trường của tài khoản nếu email này đã đăng ký và chọn Trường; null nếu chưa.
  final CampusInfo? university;

  /// Thời điểm (giờ máy) nhận được phản hồi gửi mã, để tính thời gian chờ gửi lại.
  final DateTime sentAt;

  /// Số giây còn phải chờ mới được gửi lại mã (0 nếu đã được gửi lại).
  int resendWaitSeconds(DateTime now) {
    final remainingMs =
        resendAfterSeconds * 1000 - now.difference(sentAt).inMilliseconds;
    return remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
  }
}
