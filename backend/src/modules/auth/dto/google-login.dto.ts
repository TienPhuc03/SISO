import { IsNotEmpty, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class GoogleLoginDto {
  @ApiProperty({ description: 'Firebase ID token sau khi app đăng nhập Google qua Firebase Auth' })
  @IsString()
  @IsNotEmpty({ message: 'Thiếu idToken' })
  idToken: string;
}
