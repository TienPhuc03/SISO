import { IsNotEmpty, IsNumber, IsBoolean, IsArray, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty } from '@nestjs/swagger';

export class ImuSampleDto {
  @ApiProperty({ example: 0.12 })
  @IsNumber()
  ax: number;

  @ApiProperty({ example: 0.45 })
  @IsNumber()
  ay: number;

  @ApiProperty({ example: 1.05 })
  @IsNumber()
  az: number;

  @ApiProperty({ example: 1729600000000 })
  @IsNumber()
  timestamp: number;
}

export class TelemetryPayloadDto {
  @ApiProperty({ example: 3.5, description: 'Vận tốc trung bình (m/s)' })
  @IsNumber()
  averageSpeedMps: number;

  @ApiProperty({ example: 12.5, description: 'Độ sai số vệ tinh GPS (m)' })
  @IsNumber()
  horizontalAccuracy: number;

  @ApiProperty({ example: false, description: 'Cờ phát hiện Fake GPS từ OS' })
  @IsBoolean()
  isMocked: boolean;

  @ApiProperty({ type: [ImuSampleDto], description: 'Buffer 256 mẫu gia tốc (5.12s @ 50Hz)' })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ImuSampleDto)
  imuSamples: ImuSampleDto[];
}
