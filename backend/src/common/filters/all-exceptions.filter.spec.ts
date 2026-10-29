import { ArgumentsHost, BadRequestException, HttpStatus } from '@nestjs/common';
import { AllExceptionsFilter } from './all-exceptions.filter';
import { BaseResponseDto } from '../dto/base-response.dto';

describe('AllExceptionsFilter & BaseResponseDto (Day 2 - Dev 2)', () => {
  let filter: AllExceptionsFilter;
  let mockJson: jest.Mock;
  let mockStatus: jest.Mock;
  let mockHost: ArgumentsHost;

  beforeEach(() => {
    filter = new AllExceptionsFilter();
    mockJson = jest.fn();
    mockStatus = jest.fn().mockReturnValue({ json: mockJson });
    mockHost = {
      switchToHttp: () => ({
        getResponse: () => ({ status: mockStatus }),
        getRequest: () => ({ url: '/api/v1/test', method: 'POST' }),
      }),
    } as unknown as ArgumentsHost;
  });

  it('should preserve business SisoErrorCodes on HttpException (e.g. ERR_101)', () => {
    const exception = new BadRequestException({
      code: 'ERR_101',
      message: 'INVALID_DOMAIN: Email không hợp lệ.',
    });

    filter.catch(exception, mockHost);

    expect(mockStatus).toHaveBeenCalledWith(HttpStatus.BAD_REQUEST);
    expect(mockJson).toHaveBeenCalledWith(
      expect.objectContaining({
        success: false,
        code: 'ERR_101',
        message: 'INVALID_DOMAIN: Email không hợp lệ.',
        path: '/api/v1/test',
      }),
    );
  });

  it('should scrub sensitive SQL/internal stack details on 500 Internal Server Error', () => {
    const sensitiveDbError = new Error(
      'SELECT * FROM users WHERE password_hash = "secret" failed on db.supabase.co',
    );

    filter.catch(sensitiveDbError, mockHost);

    expect(mockStatus).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    const payload = mockJson.mock.calls[0][0];
    expect(payload.success).toBe(false);
    expect(payload.code).toBe('HTTP_500');
    expect(payload.message).toBe('Đã xảy ra lỗi hệ thống nội bộ. Vui lòng thử lại sau.');
    expect(JSON.stringify(payload)).not.toContain('password_hash');
    expect(JSON.stringify(payload)).not.toContain('supabase.co');
  });

  it('should create an immutable BaseResponseDto instance', () => {
    const res = BaseResponseDto.ok('Thành công', { count: 5 });
    expect(res.success).toBe(true);
    expect(res.message).toBe('Thành công');
    expect(res.data).toEqual({ count: 5 });
    expect(Object.isFrozen(res)).toBe(true);
  });
});
