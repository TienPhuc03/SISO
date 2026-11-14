import { ArrayNotEmpty, IsArray, IsOptional, IsString, IsUUID } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ClaimLoopDto {
  @ApiProperty({
    example: ['8a65b56718a7fff', '8a65b567199ffff', '8a65b5671887fff'],
    description:
      'Các ô H3 Res 10 trên đường biên, THEO ĐÚNG THỨ TỰ chạy qua (ô đầu lặp lại ở cuối thì được bỏ qua). ' +
      'Sai thứ tự, đường biên tự cắt hoặc đi lại ô cũ → 400 ERR_302.',
  })
  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
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
