import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsIn, IsISO8601, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { GigoReviewStatus } from '../../../entities/gigo-audit-log.entity';
import { REVIEW_STATUSES } from './admin-query.dto';

export class ReviewGigoDto {
  @ApiProperty({ enum: REVIEW_STATUSES })
  @IsIn(REVIEW_STATUSES)
  status: GigoReviewStatus;

  @ApiPropertyOptional({
    description: 'Chỉ với false_positive: Phiên chạy bị loại thành hợp lệ và cộng bù km nếu thuộc Mùa giải hiện tại',
  })
  @IsOptional()
  @IsBoolean()
  restoreSession?: boolean;
}

export class BanUserDto {
  @ApiPropertyOptional({ example: '2026-12-01T00:00:00+07:00', description: 'Bỏ trống = khoá vĩnh viễn' })
  @IsOptional()
  @IsISO8601()
  until?: string;

  @ApiProperty({ example: 'Đi xe máy nhiều lần (ERR_202)' })
  @IsString()
  @MinLength(3)
  @MaxLength(200)
  reason: string;
}
