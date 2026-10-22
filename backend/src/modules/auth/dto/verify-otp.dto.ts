import { IsEmail, IsNotEmpty, Length } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class VerifyOtpDto {
  @ApiProperty({ example: 'nguyenvana@hutech.edu.vn' })
  @IsEmail()
  @IsNotEmpty()
  email: string;

  @ApiProperty({ example: '123456', description: 'Mã OTP 6 số' })
  @IsNotEmpty()
  @Length(6, 6, { message: 'Mã OTP phải đúng 6 ký tự' })
  otp: string;
}
