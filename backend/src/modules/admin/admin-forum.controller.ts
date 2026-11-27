import { Delete, Get, Param, ParseUUIDPipe, Post, Query, Request } from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { BaseResponseDto } from '../../common/dto/base-response.dto';
import { ReportQueryDto } from '../forum/dto/forum.dto';
import { AdminController } from './admin-only.decorator';
import { ForumModerationService } from './forum-moderation.service';

@AdminController()
export class AdminForumController {
  constructor(private readonly moderation: ForumModerationService) {}

  @Get('forum/reports')
  @ApiOperation({ summary: 'Báo cáo diễn đàn (mặc định chỉ báo cáo đang mở)' })
  async reports(@Query() q: ReportQueryDto) {
    return BaseResponseDto.ok('Báo cáo diễn đàn.', await this.moderation.reports(q.status));
  }

  @Post('forum/reports/:id/dismiss')
  @ApiOperation({ summary: 'Bỏ qua báo cáo (nội dung không vi phạm)' })
  async dismiss(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã bỏ qua báo cáo.', await this.moderation.dismissReport(req.user.userId, id));
  }

  @Delete('forum/posts/:id')
  @ApiOperation({ summary: 'Xoá bài bất kỳ (kèm ảnh, tym, bình luận, báo cáo)' })
  async deletePost(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã xoá bài.', await this.moderation.deletePost(req.user.userId, id));
  }

  @Delete('forum/comments/:id')
  @ApiOperation({ summary: 'Xoá bình luận bất kỳ' })
  async deleteComment(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã xoá bình luận.', await this.moderation.deleteComment(req.user.userId, id));
  }
}
