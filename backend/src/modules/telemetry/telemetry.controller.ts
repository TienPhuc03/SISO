import {
  Controller,
  Post,
  Get,
  Body,
  Headers,
  HttpCode,
  HttpStatus,
  UseGuards,
  Request,
  Query,
  Param,
  ParseUUIDPipe,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiOkResponse, ApiHeader } from '@nestjs/swagger';
import { TelemetryService } from './telemetry.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { VerifyWindowResponseDto } from './dto/verify-window-response.dto';
import { FinishSessionDto, FinishSessionResponseDto } from './dto/finish-session.dto';
import { ListSessionsQueryDto, SessionDetailResponseDto, SessionListResponseDto } from './dto/session-history.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { BaseResponseDto } from '../../common/dto/base-response.dto';

@ApiTags('Telemetry')
@Controller('api/v1/telemetry')
export class TelemetryController {
  constructor(private readonly telemetryService: TelemetryService) {}

  @Post('verify')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({
    summary: 'Kiểm định một cửa sổ 256 mẫu cảm biến (Cổng Động học + Cổng Sinh trắc)',
    description:
      'Gửi mỗi 5,12 s một lần. Cửa sổ đầu không có sessionId: server tạo Phiên chạy, trả sessionId và signingKey. ' +
      'Các cửa sổ sau gửi kèm seq tăng dần và header X-Siso-Signature (HMAC-SHA256 hex của nguyên văn body, khoá là signingKey). ' +
      'Một cửa sổ không qua Cổng Sinh trắc chỉ là cảnh báo (windowPassed = false); 2 cửa sổ liên tiếp thì Phiên chạy bị loại.',
  })
  @ApiHeader({ name: 'X-Siso-Signature', required: false, description: 'Bắt buộc từ cửa sổ thứ hai trở đi' })
  @ApiOkResponse({ type: VerifyWindowResponseDto })
  @ApiResponse({
    status: 400,
    description:
      'ERR_201 (GPS giả), ERR_202 (vượt tốc độ người, hoặc 2 cửa sổ liên tiếp nghi đi xe máy, hoặc phiên đã bị loại), ERR_205 (sai chữ ký hoặc gửi lại cửa sổ cũ): Phiên chạy bị loại. ' +
      'ERR_203 (chưa có tín hiệu vệ tinh, sai số âm hoặc > 20 m), ERR_206 (điểm GPS lệch quá 1 s ngoài thời gian cửa sổ): chỉ bỏ cửa sổ này, Phiên chạy tiếp tục.',
  })
  @ApiResponse({ status: 401, description: 'Thiếu hoặc sai JWT' })
  @ApiResponse({ status: 404, description: 'ERR_204: sessionId không tồn tại, của Sinh viên khác, hoặc đã kết thúc' })
  async verifyTelemetry(
    @Request() req,
    @Body() dto: TelemetryPayloadDto,
    @Headers('x-siso-signature') signature?: string,
  ) {
    const result = await this.telemetryService.verifyWindow(req.user.userId, dto, {
      rawBody: req.rawBody,
      signature,
    });
    return BaseResponseDto.ok('Đã kiểm định cửa sổ cảm biến.', result);
  }

  @Post('finish')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({
    summary: 'Kết thúc Phiên chạy không khép vòng (chạy tự do)',
    description:
      'Cộng quãng đường server đã kiểm định vào km của Sinh viên và trường, chuyển Phiên chạy sang COMPLETED. ' +
      'Phiên đã claim-loop thì đã COMPLETED, không gọi lại.',
  })
  @ApiOkResponse({ type: FinishSessionResponseDto })
  @ApiResponse({ status: 400, description: 'Phiên chạy đã bị loại (trả mã lý do loại, ví dụ ERR_202)' })
  @ApiResponse({ status: 401, description: 'Thiếu hoặc sai JWT' })
  @ApiResponse({ status: 404, description: 'ERR_204: sessionId không tồn tại, của Sinh viên khác, hoặc đã kết thúc' })
  async finishSession(@Request() req, @Body() dto: FinishSessionDto) {
    const result = await this.telemetryService.finishSession(req.user.userId, dto.sessionId);
    return BaseResponseDto.ok('Đã kết thúc Phiên chạy.', result);
  }

  @Get('sessions')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({
    summary: 'Lịch sử Phiên chạy của Sinh viên đang đăng nhập',
    description: 'Mới nhất trước, gồm cả Phiên đang chạy và Phiên bị loại. Không kèm vệt GPS; xem chi tiết để lấy Đường chạy.',
  })
  @ApiOkResponse({ type: SessionListResponseDto })
  @ApiResponse({ status: 400, description: 'page < 1 hoặc limit ngoài [1, 50]' })
  @ApiResponse({ status: 401, description: 'Thiếu hoặc sai JWT' })
  async listSessions(@Request() req, @Query() query: ListSessionsQueryDto) {
    const result = await this.telemetryService.listSessions(req.user.userId, query.page, query.limit);
    return BaseResponseDto.ok('Lịch sử Phiên chạy.', result);
  }

  @Get('sessions/:id')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({
    summary: 'Chi tiết một Phiên chạy: tổng, chuỗi cửa sổ (tốc độ / nhịp bước), Đường chạy GeoJSON',
  })
  @ApiOkResponse({ type: SessionDetailResponseDto })
  @ApiResponse({ status: 400, description: 'id không phải UUID' })
  @ApiResponse({ status: 401, description: 'Thiếu hoặc sai JWT' })
  @ApiResponse({ status: 404, description: 'ERR_204: Phiên chạy không tồn tại hoặc của Sinh viên khác' })
  async getSession(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    const result = await this.telemetryService.getSession(req.user.userId, id);
    return BaseResponseDto.ok('Chi tiết Phiên chạy.', result);
  }
}
