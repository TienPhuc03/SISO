import { applyDecorators, Controller, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiForbiddenResponse, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../../common/guards/account.guards';

/** Controller dưới `api/v1/admin`, chỉ user có role = 'admin' gọi được. */
export function AdminController() {
  return applyDecorators(
    Controller('api/v1/admin'),
    UseGuards(JwtAuthGuard, AdminGuard),
    ApiTags('Admin'),
    ApiBearerAuth(),
    ApiForbiddenResponse({ description: 'ERR_107: tài khoản không có quyền quản trị' }),
  );
}
