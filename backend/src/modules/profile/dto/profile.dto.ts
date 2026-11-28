import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsString, Length, Matches } from 'class-validator';

export class UpdateProfileDto {
  @ApiProperty({ example: 'Minh Chạy Bộ', description: 'Nickname 2–30 ký tự (bỏ khoảng trắng đầu/cuối)' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(2, 30)
  // Không cho ký tự điều khiển (xuống dòng, tab...) làm vỡ bố cục bảng xếp hạng.
  @Matches(/^[^\p{Cc}]+$/u, { message: 'displayName không được chứa ký tự điều khiển' })
  displayName: string;
}

export class ProfileUniversityDto {
  @ApiProperty({ example: 'UTH' })
  shortCode: string;

  @ApiProperty({ example: 'UTH', description: 'Tên ngắn hiển thị (short_name, không có thì shortCode)' })
  shortName: string;

  @ApiProperty({ example: 'ĐH Giao thông Vận tải TP.HCM' })
  name: string;

  @ApiProperty({ example: '#0B2545' })
  color: string;
}

export class ProfileDto {
  @ApiProperty({ example: '11111111-1111-4111-8111-111111111111' })
  id: string;

  @ApiProperty({ example: 'sv@ut.edu.vn' })
  email: string;

  @ApiProperty({ example: 'Minh Chạy Bộ' })
  displayName: string;

  @ApiProperty({ example: 12.4, description: 'Km cá nhân trong Mùa giải hiện tại' })
  personalKm: number;

  @ApiProperty({ example: 7, description: 'Số Phiên chạy đã hoàn thành' })
  completedRuns: number;

  @ApiProperty({
    example: '/api/v1/profile/avatar/11111111-1111-4111-8111-111111111111?v=1763632800000',
    nullable: true,
    description: 'Đường dẫn tương đối, cần JWT; v đổi mỗi lần thay ảnh',
  })
  avatarUrl: string | null;

  @ApiProperty({ type: ProfileUniversityDto, nullable: true })
  university: ProfileUniversityDto | null;
}

/** Chỉ dùng cho Swagger: hình dạng BaseResponseDto với data là ProfileDto. */
export class ProfileResponseDto {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ example: 'Hồ sơ Sinh viên.' })
  message: string;

  @ApiProperty({ type: ProfileDto })
  data: ProfileDto;

  @ApiProperty({ example: '2026-11-20T10:00:00.000Z' })
  timestamp: string;
}
