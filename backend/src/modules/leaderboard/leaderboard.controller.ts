import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiQuery, ApiResponse } from '@nestjs/swagger';
import { LeaderboardService } from './leaderboard.service';
import { BaseResponseDto } from '../../common/dto/base-response.dto';

@ApiTags('Leaderboard')
@Controller('api/v1/leaderboard')
export class LeaderboardController {
  constructor(private readonly leaderboardService: LeaderboardService) {}

  @Get('scores')
  @ApiOperation({ summary: 'Bảng xếp hạng Live theo Cụm (% Đất + % Km + Sức mạnh Tổng hợp)' })
  @ApiQuery({ name: 'cluster', required: false, description: 'Mã Cụm (THU_DUC, CENTRAL, NORTH, SOUTH); bỏ trống = mọi Cụm' })
  @ApiResponse({ status: 200, description: 'Các Trường của Cụm, cao nhất trước' })
  async getLiveScores(@Query('cluster') cluster?: string) {
    return BaseResponseDto.ok('Lấy bảng xếp hạng thành công.', await this.leaderboardService.getLiveScores(cluster || undefined));
  }

  @Get('season')
  @ApiOperation({ summary: 'Mùa giải đang mở: số Mùa, ngày bắt đầu/kết thúc, thời điểm hết hạn (ends_at)' })
  @ApiResponse({ status: 200, description: 'data = null khi không có Mùa giải nào đang mở' })
  async getActiveSeason() {
    return BaseResponseDto.ok('Lấy Mùa giải hiện tại thành công.', await this.leaderboardService.getActiveSeason());
  }

  @Get('hall-of-fame')
  @ApiOperation({ summary: 'Đại sảnh Danh vọng: Quán quân mỗi Cụm các Mùa đã qua' })
  @ApiQuery({ name: 'cluster', required: false, description: 'Mã Cụm; bỏ trống = mọi Cụm' })
  @ApiResponse({ status: 200, description: 'Danh sách các Quán quân mùa giải cũ' })
  async getHallOfFame(@Query('cluster') cluster?: string) {
    return BaseResponseDto.ok('Lấy Đại sảnh Danh vọng thành công.', await this.leaderboardService.getHallOfFame(cluster || undefined));
  }
}
