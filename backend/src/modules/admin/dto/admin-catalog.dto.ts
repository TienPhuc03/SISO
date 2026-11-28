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

  @ApiPropertyOptional({ example: 'HUTECH', description: 'Tên ngắn hiển thị trong app; bỏ trống = shortCode' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  shortName?: string | null;

  @ApiPropertyOptional({ example: 'hutech.edu.vn', nullable: true, description: 'Chỉ để tham khảo, không dùng để đăng nhập' })
  @IsOptional()
  @Matches(DOMAIN, { message: 'emailDomain phải là tên miền chữ thường, ví dụ hutech.edu.vn' })
  @MaxLength(50)
  emailDomain?: string | null;

  @ApiPropertyOptional({ example: 'Bình Thạnh', description: 'Một quận trong bảng districts; quyết định Cụm' })
  @IsString()
  @MaxLength(60)
  district: string;

  @ApiPropertyOptional({ example: 'UEH', nullable: true, description: 'Thương hiệu chung của các cơ sở' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  parentName?: string | null;

  @ApiPropertyOptional({ example: 'kinh te ueh', nullable: true, description: 'Từ khoá tìm thêm' })
  @IsOptional()
  @IsString()
  @MaxLength(300)
  aliases?: string | null;

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

export class MergeUniversityDto {
  @ApiPropertyOptional({ description: 'Trường giữ lại; Sinh viên, Ô đất, Quỹ Km và Quán quân của Trường bị gộp chuyển sang đây' })
  @IsUUID()
  targetId: string;
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
