import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

/** Kết quả kiểm định một cửa sổ 256 mẫu. */
export class VerifyWindowResultDto {
  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a', description: 'Gửi lại ở các cửa sổ sau' })
  sessionId: string;

  @ApiPropertyOptional({
    example: '9f2c…',
    description: 'Khoá HMAC của Phiên chạy; chỉ trả ở cửa sổ đầu tiên, dùng để ký các cửa sổ sau',
  })
  signingKey?: string;

  @ApiProperty({ example: true, description: 'Cửa sổ này có qua Cổng Sinh trắc không' })
  windowPassed: boolean;

  @ApiProperty({ example: 0, description: 'Số cửa sổ liên tiếp không qua; đạt 2 thì Phiên chạy bị loại' })
  consecutiveFailures: number;

  @ApiProperty({ example: true, description: 'false nếu tốc độ dưới 2,5 m/s nên Cổng Sinh trắc không xét' })
  biometricApplied: boolean;

  @ApiProperty({ example: 162, description: 'Nhịp bước (bước/phút), để hiện trên HUD' })
  cadenceSpm: number;

  @ApiProperty({ example: 2.71 })
  dominantFrequencyHz: number;

  @ApiProperty({ example: 0.57, description: 'Biên độ dao động (RMS, đơn vị G)' })
  amplitudeG: number;

  @ApiProperty({ example: 0.99, description: 'Độ rõ đỉnh nhịp bước (0..1)' })
  peakProminence: number;

  @ApiProperty({ example: 'Nhịp bước sinh học hợp lệ.' })
  message: string;
}

/** Chỉ dùng cho Swagger: hình dạng BaseResponseDto với data là VerifyWindowResultDto. */
export class VerifyWindowResponseDto {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ example: 'Đã kiểm định cửa sổ cảm biến.' })
  message: string;

  @ApiProperty({ type: VerifyWindowResultDto })
  data: VerifyWindowResultDto;

  @ApiProperty({ example: '2026-11-05T10:00:00.000Z' })
  timestamp: string;
}
