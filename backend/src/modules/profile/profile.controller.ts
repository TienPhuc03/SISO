import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  Patch,
  Put,
  Request,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiOkResponse, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { BaseResponseDto } from '../../common/dto/base-response.dto';
import { MAX_AVATAR_BYTES, ProfileService } from './profile.service';
import { ProfileResponseDto, UpdateProfileDto } from './dto/profile.dto';

@ApiTags('Profile')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('api/v1/profile')
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  @Get()
  @ApiOperation({ summary: 'Hồ sơ của Sinh viên đang đăng nhập' })
  @ApiOkResponse({ type: ProfileResponseDto })
  async getProfile(@Request() req) {
    return BaseResponseDto.ok('Hồ sơ Sinh viên.', await this.profileService.getProfile(req.user.userId));
  }

  @Patch()
  @ApiOperation({ summary: 'Đổi nickname' })
  @ApiOkResponse({ type: ProfileResponseDto })
  @ApiResponse({ status: 400, description: 'Nickname ngoài 2–30 ký tự hoặc có ký tự điều khiển' })
  async updateProfile(@Request() req, @Body() dto: UpdateProfileDto) {
    const profile = await this.profileService.updateDisplayName(req.user.userId, dto.displayName);
    return BaseResponseDto.ok('Đã cập nhật nickname.', profile);
  }

  @Put('avatar')
  // Multer dừng đọc ngay khi vượt giới hạn (413), không giữ cả file lớn trong RAM.
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_AVATAR_BYTES, files: 1 } }))
  @ApiOperation({ summary: 'Đổi ảnh đại diện (JPEG/PNG/WebP, tối đa 512 KB, trường multipart "file")' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({ schema: { type: 'object', properties: { file: { type: 'string', format: 'binary' } } } })
  @ApiOkResponse({ type: ProfileResponseDto })
  @ApiResponse({ status: 400, description: 'ERR_104: không phải ảnh JPEG/PNG/WebP hoặc thiếu file' })
  @ApiResponse({ status: 413, description: 'File lớn hơn 512 KB' })
  async uploadAvatar(@Request() req, @UploadedFile() file?: { buffer: Buffer }) {
    const profile = await this.profileService.setAvatar(req.user.userId, file?.buffer);
    return BaseResponseDto.ok('Đã cập nhật ảnh đại diện.', profile);
  }

  @Get('avatar/:userId')
  // URL có ?v=<thời điểm cập nhật> nên cache lâu được: đổi ảnh thì URL đổi.
  @Header('Cache-Control', 'private, max-age=31536000, immutable')
  @ApiOperation({ summary: 'Ảnh đại diện của một Sinh viên (byte ảnh, cần JWT)' })
  @ApiResponse({ status: 200, description: 'image/jpeg | image/png | image/webp' })
  @ApiResponse({ status: 404, description: 'ERR_105: chưa có ảnh đại diện' })
  async getAvatar(@Param('userId', ParseUUIDPipe) userId: string) {
    const { image, mimeType } = await this.profileService.getAvatar(userId);
    return new StreamableFile(image, { type: mimeType });
  }
}
