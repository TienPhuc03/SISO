import { IsNotEmpty, IsArray, IsNumber, IsOptional, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ClaimLoopDto {
  @ApiProperty({
    example: ['8a31e8464627fff', '8a31e846460ffff', '8a31e8464617fff'],
    description: 'Danh sách các ô lục giác H3 Res 10 tạo thành chu trình khép kín',
  })
  @IsArray()
  @IsNotEmpty()
  boundaryH3Indexes: string[];

  @ApiProperty({ example: 1250.5, description: 'Quãng đường chạy hợp lệ (mét)' })
  @IsNumber()
  distanceMeters: number;

  @ApiProperty({ example: 480, description: 'Thời gian chạy (giây)' })
  @IsNumber()
  durationSeconds: number;

  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a', required: false })
  @IsOptional()
  @IsString()
  arenaId?: string;
}
