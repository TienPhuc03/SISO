import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';

/**
 * [Ngày 2 - Dev 2] Global Exception Filter
 * - Chuẩn hóa phản hồi lỗi toàn hệ thống theo cấu trúc thống nhất.
 * - Giữ nguyên mã lỗi nghiệp vụ SISO (ERR_101 -> ERR_302) đối với HttpException.
 * - Tuyệt đối ẩn chi tiết nội bộ (SQL query, stack trace, đường dẫn hệ thống) khi xảy ra lỗi 500 (Security Checklist).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const isHttpException = exception instanceof HttpException;
    const status = isHttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const rawResponse = isHttpException ? exception.getResponse() : null;
    const extracted =
      typeof rawResponse === 'object' && rawResponse !== null
        ? (rawResponse as Record<string, unknown>)
        : { message: rawResponse };

    // Scrub sensitive internal details for 5xx errors
    const safeMessage =
      status >= HttpStatus.INTERNAL_SERVER_ERROR
        ? 'Đã xảy ra lỗi hệ thống nội bộ. Vui lòng thử lại sau.'
        : (extracted.message ?? 'Yêu cầu không hợp lệ.');

    const errorCode =
      typeof extracted.code === 'string'
        ? extracted.code
        : `HTTP_${status}`;

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(
        `[${request.method}] ${request.url} -> ${
          exception instanceof Error ? exception.message : 'Unhandled error'
        }`,
      );
    }

    response.status(status).json({
      success: false,
      code: errorCode,
      message: safeMessage,
      timestamp: new Date().toISOString(),
      path: request.url,
    });
  }
}
