import { Body, Delete, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Patch, Post, Query, Request } from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { BaseResponseDto } from '../../common/dto/base-response.dto';
import { AdminController } from './admin-only.decorator';
import { AntiCheatService } from './anti-cheat.service';
import { UserModerationService } from './user-moderation.service';
import { AdminAuditService } from './admin-audit.service';
import { AdminActionQueryDto, GigoLogQueryDto, TopOffendersQueryDto } from './dto/admin-query.dto';
import { BanUserDto, ReviewGigoDto } from './dto/admin-command.dto';

@AdminController()
export class AntiCheatController {
  constructor(
    private readonly antiCheat: AntiCheatService,
    private readonly moderation: UserModerationService,
    private readonly audit: AdminAuditService,
  ) {}

  @Get('universities')
  @ApiOperation({ summary: 'Danh sách Trường (id, mã, tên, đuôi email, màu)' })
  async universities() {
    return BaseResponseDto.ok('Danh sách Trường.', await this.antiCheat.universities());
  }

  @Get('gigo-logs')
  @ApiOperation({ summary: 'Nhật ký GIGO, lọc theo loại vi phạm / trường / thời gian / trạng thái duyệt' })
  async listLogs(@Query() q: GigoLogQueryDto) {
    return BaseResponseDto.ok('Nhật ký GIGO.', await this.antiCheat.listLogs(q));
  }

  @Get('gigo-logs/top-offenders')
  @ApiOperation({ summary: 'Sinh viên vi phạm nhiều nhất trong 7 hoặc 30 ngày (bỏ log báo nhầm)' })
  async topOffenders(@Query() q: TopOffendersQueryDto) {
    return BaseResponseDto.ok('Top vi phạm.', await this.antiCheat.topOffenders(q.days, q.limit));
  }

  @Patch('gigo-logs/:id/review')
  @ApiOperation({ summary: 'Kết luận nhật ký GIGO; false_positive có thể khôi phục Phiên chạy và cộng bù km' })
  async review(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReviewGigoDto) {
    const result = await this.antiCheat.review(req.user.userId, id, dto.status, dto.restoreSession);
    return BaseResponseDto.ok('Đã lưu kết luận.', result);
  }

  @Get('sessions/:id')
  @ApiOperation({ summary: 'Chi tiết Phiên chạy bất kỳ: cửa sổ, Đường chạy, chủ Phiên, nhật ký GIGO' })
  async session(@Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Chi tiết Phiên chạy.', await this.antiCheat.sessionDetail(id));
  }

  @Post('users/:id/ban')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Khoá Sinh viên (bỏ trống until = vĩnh viễn); loại các Phiên đang chạy' })
  async ban(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: BanUserDto) {
    const result = await this.moderation.ban(req.user.userId, id, dto.until ? new Date(dto.until) : null, dto.reason);
    return BaseResponseDto.ok('Đã khoá tài khoản.', result);
  }

  @Delete('users/:id/ban')
  @ApiOperation({ summary: 'Gỡ khoá Sinh viên' })
  async unban(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã gỡ khoá.', await this.moderation.unban(req.user.userId, id));
  }

  @Get('actions')
  @ApiOperation({ summary: 'Nhật ký thao tác admin' })
  async actions(@Query() q: AdminActionQueryDto) {
    return BaseResponseDto.ok('Nhật ký thao tác.', await this.audit.list(q.page, q.limit, q.targetType, q.targetId));
  }
}
