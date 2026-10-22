import { Controller, Post, Body, HttpCode, HttpStatus, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { TelemetryService } from './telemetry.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@ApiTags('Telemetry')
@Controller('api/v1/telemetry')
export class TelemetryController {
  constructor(private readonly telemetryService: TelemetryService) {}

  @Post('verify')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Kiểm định dữ liệu cảm biến GPS & IMU chống xe máy & Fake GPS' })
  @ApiResponse({ status: 200, description: 'Dữ liệu cảm biến hợp lệ' })
  @ApiResponse({ status: 400, description: 'ERR_201 (Fake GPS) hoặc ERR_202 (Đi xe máy)' })
  verifyTelemetry(@Body() dto: TelemetryPayloadDto) {
    return this.telemetryService.verifyTelemetry(dto);
  }
}
