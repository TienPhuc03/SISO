import {
  IsNumber,
  IsBoolean,
  IsArray,
  ValidateNested,
  ArrayMinSize,
  ArrayMaxSize,
  IsOptional,
  IsUUID,
  IsInt,
  Min,
  Max,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

/** Số mẫu cố định của một cửa sổ (5,12 s ở 50 Hz), theo hợp đồng #3. */
export const IMU_WINDOW_SIZE = 256;

export class ImuSampleDto {
  @ApiProperty({ example: 0.42, description: 'Gia tốc trục x, đơn vị m/s² (có cả trọng lực, chưa quy đổi)' })
  @IsNumber()
  ax: number;

  @ApiProperty({ example: -1.3, description: 'Gia tốc trục y, đơn vị m/s²' })
  @IsNumber()
  ay: number;

  @ApiProperty({ example: 9.81, description: 'Gia tốc trục z, đơn vị m/s²' })
  @IsNumber()
  az: number;

  @ApiProperty({ example: 1762300000000, description: 'Thời điểm lấy mẫu (epoch, mili giây)' })
  @IsNumber()
  timestamp: number;
}

/** Số điểm GPS tối đa một cửa sổ: GPS ~1 Hz cho ~5 điểm / 5,12 s, chừa dư cho máy báo nhanh hơn. */
export const MAX_GPS_POINTS_PER_WINDOW = 20;

export class GpsPointDto {
  @ApiProperty({ example: 10.8013, description: 'Vĩ độ (độ)' })
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat: number;

  @ApiProperty({ example: 106.7142, description: 'Kinh độ (độ)' })
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng: number;

  @ApiProperty({ example: 1762300000000, description: 'Thời điểm lấy điểm (epoch, mili giây), nằm trong cửa sổ' })
  @IsNumber()
  timestamp: number;

  // Không chặn số âm: iOS trả -1 khi chưa có tín hiệu, giống horizontalAccuracy.
  @ApiProperty({ example: 6.5, description: 'Sai số ngang của điểm (m)' })
  @IsNumber()
  accuracy: number;
}

export class TelemetryPayloadDto {
  @ApiPropertyOptional({
    example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a',
    description: 'Bỏ trống ở cửa sổ đầu tiên; các cửa sổ sau gửi sessionId server đã cấp',
  })
  @IsOptional()
  @IsUUID()
  sessionId?: string;

  @ApiPropertyOptional({
    example: 1,
    description: 'Số thứ tự cửa sổ đã ký, tăng dần trong một Phiên chạy (chống gửi lại). Bắt buộc khi có sessionId.',
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  seq?: number;

  @ApiProperty({ example: 3.2, description: 'Vận tốc trung bình trong cửa sổ (m/s), từ GPS' })
  @IsNumber()
  @Min(0)
  averageSpeedMps: number;

  @ApiProperty({
    example: 8.5,
    description: 'Sai số vệ tinh GPS (m). Giá trị âm (iOS trả -1 khi chưa có tín hiệu) bị trả ERR_203.',
  })
  @IsNumber()
  horizontalAccuracy: number;

  @ApiProperty({ example: false, description: 'Cờ phát hiện Fake GPS từ hệ điều hành' })
  @IsBoolean()
  isMocked: boolean;

  @ApiProperty({
    type: [ImuSampleDto],
    description: `Đúng ${IMU_WINDOW_SIZE} mẫu gia tốc (5,12 s @ 50 Hz), đơn vị m/s²`,
  })
  @IsArray()
  @ArrayMinSize(IMU_WINDOW_SIZE)
  @ArrayMaxSize(IMU_WINDOW_SIZE)
  @ValidateNested({ each: true })
  @Type(() => ImuSampleDto)
  imuSamples: ImuSampleDto[];

  @ApiPropertyOptional({
    type: [GpsPointDto],
    description: `Vệt GPS trong cửa sổ (tối đa ${MAX_GPS_POINTS_PER_WINDOW} điểm) để vẽ Đường chạy. Bỏ trống thì cửa sổ không có vệt.`,
  })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(MAX_GPS_POINTS_PER_WINDOW)
  @ValidateNested({ each: true })
  @Type(() => GpsPointDto)
  gpsPoints?: GpsPointDto[];
}
