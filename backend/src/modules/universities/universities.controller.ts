import { Body, Controller, Get, Put, Request, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { BaseResponseDto } from '../../common/dto/base-response.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChooseUniversityDto } from './dto/choose-university.dto';
import { UniversitiesService } from './universities.service';

@ApiTags('Universities')
@Controller('api/v1/universities')
export class UniversitiesController {
  constructor(private readonly universities: UniversitiesService) {}

  @Get()
  @ApiOperation({ summary: 'Danh mục chọn Trường: Cụm, quận (kèm Cụm) và mọi Trường' })
  async catalog() {
    return BaseResponseDto.ok('Danh mục Trường.', await this.universities.catalog());
  }

  @Put('mine')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Chọn / đổi Trường (Trường có sẵn hoặc thêm mới); trả accessToken + user mới' })
  @ApiResponse({ status: 403, description: 'ERR_112: đang khoá Trường theo Mùa giải' })
  @ApiResponse({ status: 400, description: 'ERR_113: quận không hợp lệ' })
  async choose(@Request() req, @Body() dto: ChooseUniversityDto) {
    return this.universities.choose(req.user.userId, dto);
  }
}
