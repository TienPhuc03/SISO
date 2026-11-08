/**
 * Giới hạn số request Auth theo IP trong 1 phút.
 * Đặt rộng tay vì cả trường có thể dùng chung 1 IP (Wi-Fi/NAT); việc chống dò OTP
 * đã do khoá 5 lần sai + chờ 60s theo từng email đảm nhận.
 */
export const AUTH_THROTTLE_TTL_MS = 60_000;
export const EDU_LOGIN_LIMIT_PER_MIN = 20;
export const VERIFY_OTP_LIMIT_PER_MIN = 30;
export const AUTH_THROTTLE_ERROR =
  'Quá nhiều yêu cầu đăng nhập từ thiết bị/mạng này. Vui lòng thử lại sau 1 phút.';
