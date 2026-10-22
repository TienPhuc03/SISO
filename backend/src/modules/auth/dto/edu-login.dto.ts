import { IsEmail, IsNotEmpty } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class EduLoginDto {
  @ApiProperty({
    example: 'nguyenvana@hutech.edu.vn',
    description: 'Email sinh viên thuộc các trường Đại học tại Bình Thạnh',
  })
  @IsEmail({}, { message: 'Định dạng email không hợp lệ' })
  @IsNotEmpty({ message: 'Email không được để trống' })
  email: string;
}
