import { deriveSigningKey, isValidSignature, signBody } from './telemetry-signature';

describe('telemetry-signature', () => {
  const key = deriveSigningKey('server-secret', 'session-1');
  const body = Buffer.from('{"seq":1,"averageSpeedMps":3.2}');

  it('khoá khác nhau theo từng Phiên chạy', () => {
    expect(deriveSigningKey('server-secret', 'session-2')).not.toBe(key);
  });

  it('chấp nhận chữ ký đúng', () => {
    expect(isValidSignature(key, body, signBody(key, body))).toBe(true);
  });

  it('từ chối body bị sửa, khoá sai và chữ ký sai định dạng', () => {
    const signature = signBody(key, body);

    expect(isValidSignature(key, Buffer.from('{"seq":1,"averageSpeedMps":9.9}'), signature)).toBe(false);
    expect(isValidSignature(deriveSigningKey('khac', 'session-1'), body, signature)).toBe(false);
    expect(isValidSignature(key, body, 'khong-phai-hex')).toBe(false);
  });

  it('khớp véc-tơ dùng chung với client Dart (test/telemetry_repository_test.dart)', () => {
    expect(signBody('khoá-phiên', '{"ghi":"chú tiếng Việt","v":3.2}')).toBe(
      '0c44a3010436d3f67c177f2e3e96cfbc48d2335359c18ebd74510a1226858646',
    );
  });
});
