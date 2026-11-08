import { Controller, Post, Body, HttpCode, HttpStatus, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiOkResponse } from '@nestjs/swagger';
import { TelemetryService } from './telemetry.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { VerifyWindowResponseDto } from './dto/verify-window-response.dto';
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
      'Gửi mỗi 5,12 s một lần. Cửa sổ đầu không có sessionId: server tạo Phiên chạy và trả sessionId. ' +
      'Một cửa sổ không qua Cổng Sinh trắc chỉ là cảnh báo (windowPassed = false); 2 cửa sổ liên tiếp thì Phiên chạy bị loại.',
  })
  @ApiOkResponse({ type: VerifyWindowResponseDto })
  @ApiResponse({
    status: 400,
    description:
      'ERR_201 (GPS giả), ERR_203 (sai số GPS lớn), ERR_202 (vượt tốc độ người, hoặc 2 cửa sổ liên tiếp nghi đi xe máy, hoặc phiên đã bị loại)',
  })
  @ApiResponse({ status: 401, description: 'Thiếu hoặc sai JWT' })
  @ApiResponse({ status: 404, description: 'ERR_204: sessionId không tồn tại, của Sinh viên khác, hoặc đã kết thúc' })
  async verifyTelemetry(@Request() req, @Body() dto: TelemetryPayloadDto) {
    const result = await this.telemetryService.verifyWindow(req.user.userId, dto);
    return BaseResponseDto.ok('Đã kiểm định cửa sổ cảm biến.', result);
  }
}
