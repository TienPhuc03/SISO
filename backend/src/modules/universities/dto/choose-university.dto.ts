import { IsNotEmpty, IsOptional, IsString, IsUUID, MaxLength, MinLength, ValidateIf } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';

/** Chọn Trường có sẵn (`universityId`) hoặc thêm Trường mới (`name` + `shortName` + `district`). */
export class ChooseUniversityDto {
  @ApiPropertyOptional({ description: 'Trường có sẵn trong danh sách' })
  @IsOptional()
  @IsUUID()
  universityId?: string;

  @ApiPropertyOptional({ example: 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở V' })
  @ValidateIf((o) => !o.universityId)
  @IsString()
  @MinLength(5, { message: 'Tên trường tối thiểu 5 ký tự' })
  @MaxLength(100)
  name?: string;

  @ApiPropertyOptional({ example: 'UEH Cơ sở V' })
  @ValidateIf((o) => !o.universityId)
  @IsString()
  @MinLength(2, { message: 'Tên viết tắt tối thiểu 2 ký tự' })
  @MaxLength(20)
  shortName?: string;

  @ApiPropertyOptional({ example: 'Quận 3', description: 'Một quận trong GET /universities (districts)' })
  @ValidateIf((o) => !o.universityId)
  @IsString()
  @IsNotEmpty()
  @MaxLength(60)
  district?: string;
}
