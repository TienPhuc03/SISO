import { Controller, Post, Get, Body, Query, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { TurfService } from './turf.service';
import { ClaimLoopDto } from './dto/claim-loop.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@ApiTags('Turf')
@Controller('api/v1/turf')
export class TurfController {
  constructor(private readonly turfService: TurfService) {}

  @Get('hexagons')
  @ApiOperation({ summary: 'Lấy trạng thái các ô lục giác H3 trên bản đồ' })
  @ApiQuery({ name: 'arenaId', required: false, description: 'Lọc theo ID Đấu trường' })
  async getHexagons(@Query('arenaId') arenaId?: string) {
    return this.turfService.getArenaHexagons(arenaId);
  }

  @Post('claim-loop')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Bao vây khép vòng và chiếm ô lục giác H3 cho trường' })
  @ApiResponse({ status: 200, description: 'Chiếm đất thành công và kích hoạt WebSocket' })
  @ApiResponse({ status: 400, description: 'ERR_301: Vòng lặp quá lớn (> 150 ô)' })
  async claimLoop(@Request() req, @Body() dto: ClaimLoopDto) {
    return this.turfService.claimLoop(req.user.userId, dto);
  }
}
