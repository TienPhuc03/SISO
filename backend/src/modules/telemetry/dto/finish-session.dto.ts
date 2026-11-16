import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

export class FinishSessionDto {
  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a', description: 'sessionId server đã cấp ở cửa sổ đầu' })
  @IsUUID()
  sessionId: string;
}

/** Kết quả kết thúc Phiên chạy tự do. */
export class FinishSessionResultDto {
  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a' })
  sessionId: string;

  @ApiProperty({ example: 2450.6, description: 'Quãng đường server đã cộng qua các cửa sổ hợp lệ (m)' })
  distanceMeters: number;

  @ApiProperty({ example: 860 })
  durationSeconds: number;

  @ApiProperty({ example: 2.45, description: 'Km vừa cộng cho Sinh viên và trường' })
  addedKm: number;
}

/** Chỉ dùng cho Swagger: hình dạng BaseResponseDto với data là FinishSessionResultDto. */
export class FinishSessionResponseDto {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ example: 'Đã kết thúc Phiên chạy.' })
  message: string;

  @ApiProperty({ type: FinishSessionResultDto })
  data: FinishSessionResultDto;

  @ApiProperty({ example: '2026-11-12T10:00:00.000Z' })
  timestamp: string;
}
