import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';

export const MAX_POST_IMAGES = 4;
export const MAX_POST_IMAGE_BYTES = 1024 * 1024;

export class FeedQueryDto {
  @ApiPropertyOptional({ description: 'Lọc theo Cụm' })
  @IsOptional()
  @Matches(/^[A-Z_]{2,20}$/)
  cluster?: string;

  @ApiPropertyOptional({ description: 'Lọc theo Trường' })
  @IsOptional()
  @IsUUID()
  universityId?: string;

  @ApiPropertyOptional({ description: 'Phân trang: chỉ lấy bài đăng trước thời điểm này (createdAt của bài cuối trang trước)' })
  @IsOptional()
  @IsISO8601()
  before?: string;

  @ApiPropertyOptional({ default: 20, maximum: 50 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit: number = 20;
}

/** Multipart: `body`, `sessionId` + tối đa 4 file `images` (JPEG/PNG/WebP, ≤ 1 MB). */
export class CreatePostDto {
  @ApiPropertyOptional({ maxLength: 2000 })
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  body?: string;

  @ApiPropertyOptional({ description: 'Phiên chạy hợp lệ của chính tác giả' })
  @IsOptional()
  @IsUUID()
  sessionId?: string;
}

/** Multipart: các trường bỏ trống thì giữ nguyên; `sessionId` = "" để bỏ đính kèm. */
export class UpdatePostDto {
  @ApiPropertyOptional({ maxLength: 2000 })
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  body?: string;

  @ApiPropertyOptional({ description: 'UUID Phiên chạy, hoặc chuỗi rỗng để bỏ đính kèm' })
  @IsOptional()
  @Matches(/^$|^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  sessionId?: string;

  @ApiPropertyOptional({ description: 'JSON mảng URL ảnh cũ muốn giữ (theo thứ tự); bỏ trống = giữ hết' })
  @IsOptional()
  @IsString()
  @MaxLength(4000)
  keepImages?: string;
}

export class CommentDto {
  @ApiPropertyOptional({ maxLength: 1000 })
  @IsString()
  @MinLength(1)
  @MaxLength(1000)
  body: string;
}

export class ReportDto {
  @ApiPropertyOptional({ description: 'Báo cáo một bình luận của bài này (bỏ trống = báo cáo bài)' })
  @IsOptional()
  @IsUUID()
  commentId?: string;

  @ApiPropertyOptional({ maxLength: 300 })
  @IsOptional()
  @IsString()
  @MaxLength(300)
  reason?: string;
}

export class ReportQueryDto {
  @ApiPropertyOptional({ enum: ['open', 'all'], default: 'open' })
  @IsOptional()
  @IsIn(['open', 'all'])
  status: 'open' | 'all' = 'open';
}
