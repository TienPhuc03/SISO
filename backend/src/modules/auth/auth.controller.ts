import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { EduLoginDto } from './dto/edu-login.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';

@ApiTags('Auth')
@Controller('api/v1/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('edu-login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Gửi yêu cầu đăng nhập bằng Email Sinh viên Bình Thạnh' })
  @ApiResponse({ status: 200, description: 'Gửi OTP thành công về email' })
  @ApiResponse({ status: 400, description: 'ERR_101: Email không thuộc các trường hợp lệ' })
  async requestEduLogin(@Body() dto: EduLoginDto) {
    return this.authService.requestEduLogin(dto.email);
  }

  @Post('verify-otp')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Xác thực mã OTP và cấp JWT Token' })
  @ApiResponse({ status: 200, description: 'Xác thực thành công, trả về Access Token' })
  async verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.authService.verifyOtp(dto.email, dto.otp);
  }
}
