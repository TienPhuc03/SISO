import { IsNotEmpty, IsArray, IsOptional, IsUUID } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ClaimLoopDto {
  @ApiProperty({
    example: ['8a31e8464627fff', '8a31e846460ffff', '8a31e8464617fff'],
    description: 'Danh sách các ô lục giác H3 Res 10 tạo thành chu trình khép kín',
  })
  @IsArray()
  @IsNotEmpty()
  boundaryH3Indexes: string[];

  @ApiProperty({
    example: 'c1f67b4e-28c4-42b7-a35b-c2e3919e9140',
    description: 'Phiên chạy do POST /telemetry/verify cấp. Quãng đường và thời gian lấy từ phiên này, không nhận từ client.',
  })
  @IsUUID()
  sessionId: string;

  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a', required: false })
  @IsOptional()
  @IsUUID()
  arenaId?: string;
}
