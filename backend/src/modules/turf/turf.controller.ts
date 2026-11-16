import { Controller, Post, Get, Body, Query, UseGuards, Request, ParseUUIDPipe } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiQuery, ApiOkResponse } from '@nestjs/swagger';
import { TurfService } from './turf.service';
import { ClaimLoopDto } from './dto/claim-loop.dto';
import { ArenaListResponseDto, HexagonListResponseDto } from './dto/turf-response.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { BaseResponseDto } from '../../common/dto/base-response.dto';

@ApiTags('Turf')
@Controller('api/v1/turf')
export class TurfController {
  constructor(private readonly turfService: TurfService) {}

  @Get('arenas')
  @ApiOperation({ summary: 'Danh sách Đấu trường đang hoạt động (số ô thật + ranh giới GeoJSON)' })
  @ApiOkResponse({ type: ArenaListResponseDto })
  async getArenas() {
    return BaseResponseDto.ok('Lấy danh sách Đấu trường thành công.', await this.turfService.getArenas());
  }

  @Get('hexagons')
  @ApiOperation({ summary: 'Lấy trạng thái các ô lục giác H3 trên bản đồ' })
  @ApiQuery({ name: 'arenaId', required: false, description: 'UUID Đấu trường; bỏ trống để lấy toàn bộ ô' })
  @ApiOkResponse({ type: HexagonListResponseDto })
  @ApiResponse({ status: 400, description: 'arenaId không phải UUID' })
  @ApiResponse({ status: 404, description: 'ERR_303: Không tìm thấy Đấu trường' })
  async getHexagons(@Query('arenaId', new ParseUUIDPipe({ optional: true })) arenaId?: string) {
    return BaseResponseDto.ok('Lấy trạng thái ô đất thành công.', await this.turfService.getArenaHexagons(arenaId));
  }

  @Post('claim-loop')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Bao vây khép vòng và chiếm ô lục giác H3 cho trường' })
  @ApiResponse({ status: 200, description: 'Chiếm đất thành công và kích hoạt WebSocket' })
  @ApiResponse({ status: 400, description: 'ERR_301: Vòng lặp quá lớn (> 150 ô); ERR_302: đường biên tự cắt / sai thứ tự / chưa khép (ô cuối không liền kề ô đầu); ERR_304: có ô ngoài Đấu trường (hoặc ngoài khu thi đấu nếu không gửi arenaId); hoặc mã loại của Phiên chạy đã bị loại' })
  @ApiResponse({ status: 404, description: 'ERR_204: sessionId không tồn tại, của Sinh viên khác, hoặc đã dùng; ERR_303: arenaId không tồn tại' })
  async claimLoop(@Request() req, @Body() dto: ClaimLoopDto) {
    const { message, ...result } = await this.turfService.claimLoop(req.user.userId, dto);
    return BaseResponseDto.ok(message, result);
  }
}
