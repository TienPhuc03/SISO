import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { GigoReviewStatus } from '../../../entities/gigo-audit-log.entity';

export const REVIEW_STATUSES: GigoReviewStatus[] = ['pending', 'confirmed_cheat', 'false_positive'];

export class PageQueryDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page: number = 1;

  @ApiPropertyOptional({ default: 20, maximum: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 20;
}

export class GigoLogQueryDto extends PageQueryDto {
  @ApiPropertyOptional({ example: 'ERR_202', description: 'Loại vi phạm (rejection_type)' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  type?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  universityId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  userId?: string;

  @ApiPropertyOptional({ example: '2026-11-01T00:00:00+07:00' })
  @IsOptional()
  @IsISO8601()
  from?: string;

  @ApiPropertyOptional({ example: '2026-11-30T00:00:00+07:00', description: 'Không bao gồm mốc này' })
  @IsOptional()
  @IsISO8601()
  to?: string;

  @ApiPropertyOptional({ enum: REVIEW_STATUSES })
  @IsOptional()
  @IsIn(REVIEW_STATUSES)
  reviewStatus?: GigoReviewStatus;
}

export class TopOffendersQueryDto {
  @ApiPropertyOptional({ enum: [7, 30], default: 7 })
  @IsOptional()
  @Type(() => Number)
  @IsIn([7, 30])
  days: number = 7;

  @ApiPropertyOptional({ default: 10, maximum: 50 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit: number = 10;
}

export class AdminActionQueryDto extends PageQueryDto {
  @ApiPropertyOptional({ enum: ['user', 'gigo_log', 'season', 'university', 'arena'] })
  @IsOptional()
  @IsIn(['user', 'gigo_log', 'season', 'university', 'arena'])
  targetType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(64)
  targetId?: string;
}
