import { Body, Delete, Get, Param, ParseIntPipe, ParseUUIDPipe, Patch, Post, Query, Request } from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { BaseResponseDto } from '../../common/dto/base-response.dto';
import { AdminController } from './admin-only.decorator';
import { CatalogService } from './catalog.service';
import { StatsService } from './stats.service';
import { StudentsService } from './students.service';
import { PageQueryDto } from './dto/admin-query.dto';
import {
  CreateSeasonDto,
  MergeUniversityDto,
  StatsRangeQueryDto,
  StudentQueryDto,
  UniversityDto,
  UpdateArenaDto,
  UpdateSeasonDto,
} from './dto/admin-catalog.dto';

@AdminController()
export class AdminManageController {
  constructor(
    private readonly stats: StatsService,
    private readonly catalog: CatalogService,
    private readonly students: StudentsService,
  ) {}

  // ---------- Tổng quan ----------

  @Get('stats/overview')
  @ApiOperation({ summary: 'Chỉ số nhanh: DAU/WAU/MAU, Sinh viên mới, Phiên hôm nay, Phiên kẹt, chờ duyệt' })
  async overview() {
    return BaseResponseDto.ok('Tổng quan.', await this.stats.overview());
  }

  @Get('stats/by-hour')
  @ApiOperation({ summary: 'Số Phiên chạy theo giờ trong ngày (giờ VN) trong `days` ngày qua' })
  async byHour(@Query() q: StatsRangeQueryDto) {
    return BaseResponseDto.ok('Phiên theo giờ.', await this.stats.byHour(q.days));
  }

  @Get('stats/daily')
  @ApiOperation({ summary: 'Theo ngày (giờ VN): Phiên, Phiên bị loại, DAU, Sinh viên mới' })
  async daily(@Query() q: StatsRangeQueryDto) {
    return BaseResponseDto.ok('Thống kê theo ngày.', await this.stats.daily(q.days));
  }

  @Get('stats/stuck-sessions')
  @ApiOperation({ summary: 'Phiên chạy vẫn ACTIVE sau hơn 2 giờ (tối đa 50)' })
  async stuck() {
    return BaseResponseDto.ok('Phiên bị kẹt.', await this.stats.stuckSessions());
  }

  // ---------- Mùa giải ----------

  @Get('seasons')
  @ApiOperation({ summary: 'Mọi Mùa giải kèm Quán quân (nếu có)' })
  async seasons() {
    return BaseResponseDto.ok('Danh sách Mùa giải.', await this.catalog.seasons());
  }

  @Post('seasons')
  @ApiOperation({ summary: 'Tạo Mùa giải; isActive = true thì đóng cờ các Mùa giải khác' })
  async createSeason(@Request() req, @Body() dto: CreateSeasonDto) {
    return BaseResponseDto.ok('Đã tạo Mùa giải.', await this.catalog.createSeason(req.user.userId, dto));
  }

  @Patch('seasons/:number')
  @ApiOperation({ summary: 'Sửa ngày / bật Mùa giải' })
  async updateSeason(@Request() req, @Param('number', ParseIntPipe) n: number, @Body() dto: UpdateSeasonDto) {
    return BaseResponseDto.ok('Đã cập nhật Mùa giải.', await this.catalog.updateSeason(req.user.userId, n, dto));
  }

  @Delete('seasons/:number')
  @ApiOperation({ summary: 'Xoá Mùa giải chưa mở và chưa có Quán quân' })
  async deleteSeason(@Request() req, @Param('number', ParseIntPipe) n: number) {
    return BaseResponseDto.ok('Đã xoá Mùa giải.', await this.catalog.deleteSeason(req.user.userId, n));
  }

  // ---------- Trường ----------

  @Post('universities')
  @ApiOperation({ summary: 'Thêm Trường (cơ sở thi đấu, đã duyệt)' })
  async createUniversity(@Request() req, @Body() dto: UniversityDto) {
    return BaseResponseDto.ok('Đã thêm Trường.', await this.catalog.createUniversity(req.user.userId, dto));
  }

  @Patch('universities/:id')
  @ApiOperation({ summary: 'Sửa Trường' })
  async updateUniversity(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UniversityDto) {
    return BaseResponseDto.ok('Đã cập nhật Trường.', await this.catalog.updateUniversity(req.user.userId, id, dto));
  }

  @Post('universities/:id/verify')
  @ApiOperation({ summary: 'Duyệt Trường Sinh viên tự thêm' })
  async verifyUniversity(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã duyệt Trường.', await this.catalog.verifyUniversity(req.user.userId, id));
  }

  @Post('universities/:id/merge')
  @ApiOperation({ summary: 'Gộp Trường trùng vào Trường khác (chuyển Sinh viên, Ô đất, Quỹ Km, Quán quân rồi xoá)' })
  async mergeUniversity(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: MergeUniversityDto) {
    return BaseResponseDto.ok('Đã gộp Trường.', await this.catalog.mergeUniversity(req.user.userId, id, dto));
  }

  @Delete('universities/:id')
  @ApiOperation({ summary: 'Xoá Trường chưa có Sinh viên' })
  async deleteUniversity(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã xoá Trường.', await this.catalog.deleteUniversity(req.user.userId, id));
  }

  // ---------- Đấu trường ----------

  @Get('arenas')
  @ApiOperation({ summary: 'Mọi Đấu trường (kể cả đang tắt) kèm số ô và số ô có chủ' })
  async arenas() {
    return BaseResponseDto.ok('Danh sách Đấu trường.', await this.catalog.arenas());
  }

  @Patch('arenas/:id')
  @ApiOperation({ summary: 'Bật/tắt hoặc đổi tên Đấu trường' })
  async updateArena(@Request() req, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateArenaDto) {
    return BaseResponseDto.ok('Đã cập nhật Đấu trường.', await this.catalog.updateArena(req.user.userId, id, dto));
  }

  // ---------- Sinh viên ----------

  @Get('users')
  @ApiOperation({ summary: 'Tìm Sinh viên theo email / tên, lọc theo Trường, đang khoá, admin' })
  async listStudents(@Query() q: StudentQueryDto) {
    return BaseResponseDto.ok('Danh sách Sinh viên.', await this.students.list(q));
  }

  @Get('users/:id')
  @ApiOperation({ summary: 'Chi tiết Sinh viên và thống kê Phiên chạy' })
  async student(@Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Chi tiết Sinh viên.', await this.students.detail(id));
  }

  @Get('users/:id/sessions')
  @ApiOperation({ summary: 'Lịch sử Phiên chạy của Sinh viên' })
  async studentSessions(@Param('id', ParseUUIDPipe) id: string, @Query() q: PageQueryDto) {
    return BaseResponseDto.ok('Lịch sử Phiên chạy.', await this.students.sessions(id, q.page, q.limit));
  }

  @Delete('users/:id/avatar')
  @ApiOperation({ summary: 'Gỡ ảnh đại diện của Sinh viên' })
  async removeAvatar(@Request() req, @Param('id', ParseUUIDPipe) id: string) {
    return BaseResponseDto.ok('Đã gỡ ảnh đại diện.', await this.students.removeAvatar(req.user.userId, id));
  }
}
