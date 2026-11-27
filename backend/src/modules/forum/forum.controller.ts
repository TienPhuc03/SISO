import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
  Request,
  UploadedFiles,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FilesInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { BaseResponseDto } from '../../common/dto/base-response.dto';
import { NotBannedGuard } from '../../common/guards/account.guards';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  CommentDto,
  CreatePostDto,
  FeedQueryDto,
  MAX_POST_IMAGE_BYTES,
  MAX_POST_IMAGES,
  ReportDto,
  UpdatePostDto,
} from './dto/forum.dto';
import { ForumService, UploadedImage } from './forum.service';

const images = () =>
  FilesInterceptor('images', MAX_POST_IMAGES, { limits: { fileSize: MAX_POST_IMAGE_BYTES, files: MAX_POST_IMAGES } });

/** Đọc cần đăng nhập; viết (đăng, tym, bình luận, báo cáo) cần đã chọn Trường và không bị khoá (NotBannedGuard). */
@ApiTags('Forum')
@ApiBearerAuth()
@Controller('api/v1/forum')
@UseGuards(JwtAuthGuard)
export class ForumController {
  constructor(private readonly forum: ForumService) {}

  @Get('posts')
  @ApiOperation({ summary: 'Bảng tin, mới nhất trước; lọc theo Cụm / Trường; phân trang bằng `before`' })
  async feed(@Request() req, @Query() q: FeedQueryDto) {
    return BaseResponseDto.ok('Bảng tin.', await this.forum.feed(req.user.userId, q));
  }

  @Get('posts/:id')
  async post(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Bài đăng.', await this.forum.getPost(req.user.userId, id));
  }

  @Post('posts')
  @UseGuards(NotBannedGuard)
  @UseInterceptors(images())
  @ApiConsumes('multipart/form-data')
  @ApiOperation({ summary: 'Đăng bài: `body`, `sessionId` (tuỳ chọn), tối đa 4 file `images`' })
  @ApiResponse({ status: 400, description: 'ERR_104 ảnh sai / quá 1 MB | ERR_114 chưa bật lưu ảnh | ERR_115 bài rỗng | ERR_116 Phiên chạy không hợp lệ' })
  async create(@Request() req, @Body() dto: CreatePostDto, @UploadedFiles() files?: UploadedImage[]) {
    return BaseResponseDto.ok('Đã đăng bài.', await this.forum.createPost(req.user.userId, dto, files));
  }

  @Patch('posts/:id')
  @UseGuards(NotBannedGuard)
  @UseInterceptors(images())
  @ApiConsumes('multipart/form-data')
  @ApiOperation({ summary: 'Sửa bài của mình: `body`, `sessionId` ("" = bỏ), `keepImages` (JSON URL ảnh giữ lại), `images` mới' })
  @ApiResponse({ status: 403, description: 'ERR_117: không phải bài của mình' })
  async update(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdatePostDto, @UploadedFiles() files?: UploadedImage[]) {
    return BaseResponseDto.ok('Đã sửa bài.', await this.forum.updatePost(req.user.userId, id, dto, files));
  }

  @Delete('posts/:id')
  @ApiOperation({ summary: 'Xoá bài của mình (kèm ảnh, tym, bình luận)' })
  async remove(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã xoá bài.', await this.forum.deletePost(req.user.userId, id));
  }

  @Put('posts/:id/like')
  @UseGuards(NotBannedGuard)
  async like(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã thả tym.', await this.forum.like(req.user.userId, id, true));
  }

  @Delete('posts/:id/like')
  @UseGuards(NotBannedGuard)
  async unlike(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã bỏ tym.', await this.forum.like(req.user.userId, id, false));
  }

  @Get('posts/:id/comments')
  async comments(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Bình luận.', await this.forum.comments(req.user.userId, id));
  }

  @Post('posts/:id/comments')
  @UseGuards(NotBannedGuard)
  async addComment(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CommentDto) {
    return BaseResponseDto.ok('Đã bình luận.', await this.forum.addComment(req.user.userId, id, dto.body));
  }

  @Patch('comments/:id')
  @UseGuards(NotBannedGuard)
  async updateComment(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CommentDto) {
    return BaseResponseDto.ok('Đã sửa bình luận.', await this.forum.updateComment(req.user.userId, id, dto.body));
  }

  @Delete('comments/:id')
  async deleteComment(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã xoá bình luận.', await this.forum.deleteComment(req.user.userId, id));
  }

  @Post('posts/:id/report')
  @ApiOperation({ summary: 'Báo cáo bài (hoặc một bình luận của bài qua `commentId`) cho admin' })
  async report(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReportDto) {
    return BaseResponseDto.ok('Đã gửi báo cáo.', await this.forum.report(req.user.userId, id, dto.commentId, dto.reason));
  }
}
