/// Trường đại học của sinh viên (khớp `university` trong response Auth).
class CampusInfo {
  const CampusInfo({
    required this.id,
    required this.shortCode,
    required this.name,
    required this.color,
  });

  final String id;
  final String shortCode;
  final String name;

  /// Mã màu dạng `#RRGGBB`
  final String color;

  factory CampusInfo.fromJson(Map<String, dynamic> json) => CampusInfo(
        id: json['id'] as String,
        shortCode: json['shortCode'] as String,
        name: json['name'] as String,
        color: json['color'] as String,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'shortCode': shortCode, 'name': name, 'color': color};
}

/// Sinh viên đã đăng nhập.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.university,
  });

  final String id;
  final String email;
  final String displayName;
  final CampusInfo university;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: (json['displayName'] as String?) ?? '',
        university:
            CampusInfo.fromJson(json['university'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'university': university.toJson(),
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
  final CampusInfo university;

  /// Thời điểm (giờ máy) nhận được phản hồi gửi mã, để tính thời gian chờ gửi lại.
  final DateTime sentAt;

  /// Số giây còn phải chờ mới được gửi lại mã (0 nếu đã được gửi lại).
  int resendWaitSeconds(DateTime now) {
    final remainingMs =
        resendAfterSeconds * 1000 - now.difference(sentAt).inMilliseconds;
    return remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
  }
}
