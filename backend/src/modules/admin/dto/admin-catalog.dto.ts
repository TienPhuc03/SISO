import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  IsUrl,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { PageQueryDto } from './admin-query.dto';

const HEX = /^#[0-9A-Fa-f]{6}$/;
const DOMAIN = /^[a-z0-9-]+(\.[a-z0-9-]+)+$/;

export class StatsRangeQueryDto {
  @ApiPropertyOptional({ default: 30, minimum: 1, maximum: 90 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(90)
  days: number = 30;
}

export class CreateSeasonDto {
  @ApiPropertyOptional({ description: 'Bỏ trống = số lớn nhất + 1' })
  @IsOptional()
  @IsInt()
  @Min(1)
  seasonNumber?: number;

  @ApiPropertyOptional({ example: '2026-12-01' })
  @IsISO8601({ strict: true })
  startDate: string;

  @ApiPropertyOptional({ example: '2026-12-31' })
  @IsISO8601({ strict: true })
  endDate: string;

  @ApiPropertyOptional({ default: false, description: 'true = mở Mùa giải này, đóng cờ các Mùa giải khác' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdateSeasonDto {
  @ApiPropertyOptional() @IsOptional() @IsISO8601({ strict: true }) startDate?: string;
  @ApiPropertyOptional() @IsOptional() @IsISO8601({ strict: true }) endDate?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isActive?: boolean;
}

export class UniversityDto {
  @ApiPropertyOptional({ example: 'HUTECH' })
  @IsString()
  @MinLength(2)
  @MaxLength(20)
  shortCode: string;

  @ApiPropertyOptional({ example: 'ĐH Công Nghệ TP.HCM' })
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  name: string;

  @ApiPropertyOptional({ example: 'hutech.edu.vn', description: 'Đuôi email gốc; subdomain tự được chấp nhận' })
  @Matches(DOMAIN, { message: 'emailDomain phải là tên miền chữ thường, ví dụ hutech.edu.vn' })
  @MaxLength(50)
  emailDomain: string;

  @ApiPropertyOptional({ example: '#FFCC00' })
  @Matches(HEX, { message: 'hexColor phải có dạng #RRGGBB' })
  hexColor: string;

  @ApiPropertyOptional({ example: '#1A1A1A', nullable: true })
  @IsOptional()
  @Matches(HEX, { message: 'secondaryColor phải có dạng #RRGGBB' })
  secondaryColor?: string | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsUrl({ protocols: ['https'], require_protocol: true })
  logoUrl?: string | null;
}

export class UpdateArenaDto {
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isActive?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsString() @MinLength(2) @MaxLength(100) name?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) description?: string;
}

export class StudentQueryDto extends PageQueryDto {
  @ApiPropertyOptional({ description: 'Tìm theo email hoặc tên hiển thị' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  q?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  universityId?: string;

  @ApiPropertyOptional({ enum: ['banned', 'admin'] })
  @IsOptional()
  @IsIn(['banned', 'admin'])
  status?: 'banned' | 'admin';
}
