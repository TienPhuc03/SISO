import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

/**
 * [Ngày 2 - Dev 2] Base Response DTO chuẩn hóa cấu trúc phản hồi REST API SISO
 */
export class BaseResponseDto<T = unknown> {
  @ApiProperty({ example: true, description: 'Trạng thái xử lý thành công hay thất bại' })
  readonly success: boolean;

  @ApiProperty({ example: 'Thao tác thành công.', description: 'Thông báo kết quả' })
  readonly message: string;

  @ApiPropertyOptional({ description: 'Dữ liệu trả về (bất biến)' })
  readonly data?: T;

  @ApiProperty({ example: '2026-10-28T07:00:00.000Z' })
  readonly timestamp: string;

  constructor(params: { success?: boolean; message: string; data?: T }) {
    this.success = params.success ?? true;
    this.message = params.message;
    this.data = params.data;
    this.timestamp = new Date().toISOString();
    Object.freeze(this);
  }

  static ok<T>(message: string, data?: T): BaseResponseDto<T> {
    return new BaseResponseDto<T>({ success: true, message, data });
  }
}
