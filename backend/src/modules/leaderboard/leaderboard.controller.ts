import { Controller, Get } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { LeaderboardService } from './leaderboard.service';
import { BaseResponseDto } from '../../common/dto/base-response.dto';

@ApiTags('Leaderboard')
@Controller('api/v1/leaderboard')
export class LeaderboardController {
  constructor(private readonly leaderboardService: LeaderboardService) {}

  @Get('scores')
  @ApiOperation({ summary: 'Lấy Bảng xếp hạng Live (% Đất + % Km + Điểm Tổng lực Mùa giải)' })
  @ApiResponse({ status: 200, description: 'Danh sách xếp hạng 5 trường Bình Thạnh' })
  async getLiveScores() {
    return BaseResponseDto.ok('Lấy bảng xếp hạng thành công.', await this.leaderboardService.getLiveScores());
  }

  @Get('hall-of-fame')
  @ApiOperation({ summary: 'Lấy lịch sử Đại Sảnh Danh Vọng (Hall of Fame) các mùa giải' })
  @ApiResponse({ status: 200, description: 'Danh sách các Quán quân mùa giải cũ' })
  async getHallOfFame() {
    return BaseResponseDto.ok('Lấy Đại sảnh Danh vọng thành công.', await this.leaderboardService.getHallOfFame());
  }
}
