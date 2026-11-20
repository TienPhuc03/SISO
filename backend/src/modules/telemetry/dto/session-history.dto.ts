import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';
import { RunStatus } from '../../../entities/running-session.entity';

export const MAX_HISTORY_PAGE_SIZE = 50;

export class ListSessionsQueryDto {
  @ApiPropertyOptional({ example: 1, default: 1, description: 'Trang, bắt đầu từ 1' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page: number = 1;

  @ApiPropertyOptional({ example: 20, default: 20, maximum: MAX_HISTORY_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_HISTORY_PAGE_SIZE)
  limit: number = 20;
}

/** Một dòng trong Lịch sử Phiên chạy (không kèm vệt GPS cho nhẹ). */
export class SessionSummaryDto {
  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a' })
  sessionId: string;

  @ApiProperty({ example: 'COMPLETED', enum: ['ACTIVE', 'REJECTED', 'COMPLETED'] })
  status: RunStatus;

  @ApiProperty({ example: 'FREE_RUN', enum: ['FREE_RUN', 'ARENA_LOOP'] })
  sessionType: string;

  @ApiProperty({ example: 2450.6, description: 'Quãng đường server đã kiểm định (m)' })
  distanceMeters: number;

  @ApiProperty({ example: 860, description: 'Thời gian di chuyển (s), không tính lúc Tạm dừng' })
  durationSeconds: number;

  @ApiProperty({ example: 0, description: 'Số ô đã chiếm nếu khép vòng' })
  hexCount: number;

  @ApiProperty({ example: null, nullable: true, description: 'Mã lỗi nếu Phiên bị loại, ví dụ ERR_202' })
  rejectionReason: string | null;

  @ApiProperty({ example: '2026-11-20T01:00:00.000Z' })
  startedAt: Date;

  @ApiProperty({ example: '2026-11-20T01:15:00.000Z', nullable: true, description: 'null khi còn ACTIVE' })
  finishedAt: Date | null;
}

export class SessionWindowPointDto {
  @ApiProperty({ example: 3 })
  seq: number;

  @ApiProperty({ example: 2.85 })
  speedMps: number;

  @ApiProperty({ example: 168 })
  cadenceSpm: number;

  @ApiProperty({ example: true, description: 'false = cửa sổ chỉ bị cảnh báo ở Cổng Sinh trắc' })
  passed: boolean;

  @ApiProperty({ example: '2026-11-20T01:00:15.360Z' })
  recordedAt: Date;
}

export class GeoJsonMultiLineStringDto {
  @ApiProperty({ example: 'MultiLineString' })
  type: 'MultiLineString';

  @ApiProperty({
    example: [[[106.7142, 10.8013], [106.7147, 10.8016]]],
    description: 'Mỗi phần tử là một đoạn [lng, lat]; tách đoạn ở chỗ Tạm dừng / mất tín hiệu > 15 s',
  })
  coordinates: number[][][];
}

export class SessionDetailDto extends SessionSummaryDto {
  @ApiProperty({ type: [SessionWindowPointDto], description: 'Chuỗi cửa sổ cho biểu đồ tốc độ / nhịp bước' })
  windows: SessionWindowPointDto[];

  @ApiProperty({ type: GeoJsonMultiLineStringDto })
  route: GeoJsonMultiLineStringDto;
}

/** Chỉ dùng cho Swagger: hình dạng BaseResponseDto. */
export class SessionListResponseDto {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ example: 'Lịch sử Phiên chạy.' })
  message: string;

  @ApiProperty({ type: [SessionSummaryDto] })
  data: SessionSummaryDto[];

  @ApiProperty({ example: '2026-11-20T10:00:00.000Z' })
  timestamp: string;
}

/** Chỉ dùng cho Swagger: hình dạng BaseResponseDto. */
export class SessionDetailResponseDto {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ example: 'Chi tiết Phiên chạy.' })
  message: string;

  @ApiProperty({ type: SessionDetailDto })
  data: SessionDetailDto;

  @ApiProperty({ example: '2026-11-20T10:00:00.000Z' })
  timestamp: string;
}
