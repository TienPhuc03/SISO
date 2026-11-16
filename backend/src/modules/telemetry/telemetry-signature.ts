import { createHmac, timingSafeEqual } from 'crypto';

/**
 * Chữ ký HMAC-SHA256 cho cửa sổ cảm biến (Timeline Ngày 8-9, SRS NFR-05, ticket #10).
 *
 * Mỗi Phiên chạy có khoá riêng, suy ra từ bí mật của server nên không phải lưu vào DB.
 * Client nhận khoá ở cửa sổ đầu tiên rồi ký nguyên văn body JSON của các cửa sổ sau; ký trên
 * byte thô để Dart và JS không phải thống nhất cách in số thực.
 *
 * Giới hạn: khoá nằm trên máy client, nên chữ ký chặn sửa gói tin và gửi lại cửa sổ cũ,
 * nhưng người tự chặn TLS trên chính máy mình vẫn đọc được khoá.
 */
export function deriveSigningKey(serverSecret: string, sessionId: string): string {
  return createHmac('sha256', serverSecret).update(`telemetry-signing:${sessionId}`).digest('hex');
}

export function signBody(signingKey: string, body: Buffer | string): string {
  return createHmac('sha256', signingKey).update(body).digest('hex');
}

export function isValidSignature(signingKey: string, body: Buffer, signature: string): boolean {
  const expected = Buffer.from(signBody(signingKey, body), 'hex');
  const given = Buffer.from(signature, 'hex');
  return given.length === expected.length && timingSafeEqual(given, expected);
}
