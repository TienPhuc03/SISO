import { Controller, Post, Get, Body, HttpCode, HttpStatus, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { SkipThrottle, Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { EduLoginDto } from './dto/edu-login.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AUTH_THROTTLE_TTL_MS, EDU_LOGIN_LIMIT_PER_MIN, VERIFY_OTP_LIMIT_PER_MIN } from './auth-throttle';

@ApiTags('Auth')
@Controller('api/v1/auth')
@UseGuards(ThrottlerGuard)
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('edu-login')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: EDU_LOGIN_LIMIT_PER_MIN, ttl: AUTH_THROTTLE_TTL_MS } })
  @ApiOperation({ summary: 'Gửi mã OTP về Email Sinh viên 5 trường Bình Thạnh' })
  @ApiResponse({ status: 200, description: 'Gửi OTP thành công về email' })
  @ApiResponse({ status: 400, description: 'ERR_101: Email không thuộc trường hợp lệ | ERR_103: Gửi lại quá nhanh (60s)' })
  @ApiResponse({ status: 429, description: 'Quá nhiều yêu cầu từ cùng IP' })
  async requestEduLogin(@Body() dto: EduLoginDto) {
    return this.authService.requestEduLogin(dto.email);
  }

  @Post('verify-otp')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: VERIFY_OTP_LIMIT_PER_MIN, ttl: AUTH_THROTTLE_TTL_MS } })
  @ApiOperation({ summary: 'Xác thực mã OTP và cấp JWT Token (hạn 7 ngày)' })
  @ApiResponse({ status: 200, description: 'Xác thực thành công, trả về Access Token' })
  @ApiResponse({ status: 400, description: 'ERR_102: OTP sai/hết hạn | ERR_103: Sai quá 5 lần' })
  @ApiResponse({ status: 429, description: 'Quá nhiều yêu cầu từ cùng IP' })
  async verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.authService.verifyOtp(dto.email, dto.otp);
  }

  @Get('me')
  @SkipThrottle()
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Thông tin tài khoản của JWT hiện tại' })
  @ApiResponse({ status: 200, description: 'Token hợp lệ, trả về user và trường' })
  @ApiResponse({ status: 401, description: 'Token thiếu, sai hoặc hết hạn' })
  async me(@Request() req) {
    return this.authService.getMe(req.user.userId);
  }
}
