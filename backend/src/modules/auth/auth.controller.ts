import { Controller, Post, Get, Body, HttpCode, HttpStatus, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { SkipThrottle, Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { EmailLoginDto } from './dto/email-login.dto';
import { GoogleLoginDto } from './dto/google-login.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';
import { JwtAuthGuard } from './jwt-auth.guard';
import {
  AUTH_THROTTLE_TTL_MS,
  EMAIL_LOGIN_LIMIT_PER_MIN,
  GOOGLE_LOGIN_LIMIT_PER_MIN,
  VERIFY_OTP_LIMIT_PER_MIN,
} from './auth-throttle';

@ApiTags('Auth')
@Controller('api/v1/auth')
@UseGuards(ThrottlerGuard)
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('email-login')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: EMAIL_LOGIN_LIMIT_PER_MIN, ttl: AUTH_THROTTLE_TTL_MS } })
  @ApiOperation({ summary: 'Gửi mã OTP về email (email bất kỳ)' })
  @ApiResponse({ status: 200, description: 'Gửi OTP thành công về email' })
  @ApiResponse({ status: 400, description: 'ERR_103: Gửi lại quá nhanh (60s)' })
  @ApiResponse({ status: 429, description: 'Quá nhiều yêu cầu từ cùng IP' })
  async requestEmailLogin(@Body() dto: EmailLoginDto) {
    return this.authService.requestEmailLogin(dto.email);
  }

  @Post('google')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: GOOGLE_LOGIN_LIMIT_PER_MIN, ttl: AUTH_THROTTLE_TTL_MS } })
  @ApiOperation({ summary: 'Đổi Firebase ID token (đăng nhập Google) lấy JWT SISO' })
  @ApiResponse({ status: 200, description: 'Đăng nhập thành công, trả về Access Token' })
  @ApiResponse({ status: 400, description: 'ERR_110: máy chủ chưa bật đăng nhập Google' })
  @ApiResponse({ status: 401, description: 'ERR_111: ID token sai/hết hạn hoặc email chưa xác minh' })
  async loginWithGoogle(@Body() dto: GoogleLoginDto) {
    return this.authService.loginWithGoogle(dto.idToken);
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
  @ApiResponse({ status: 200, description: 'Token hợp lệ, trả về user, trường và accessToken mới (gia hạn phiên)' })
  @ApiResponse({ status: 401, description: 'Token thiếu, sai hoặc hết hạn' })
  async me(@Request() req) {
    return this.authService.getMe(req.user.userId);
  }
}
