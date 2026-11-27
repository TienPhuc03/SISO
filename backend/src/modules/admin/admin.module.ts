import { Module } from '@nestjs/common';
import { TelemetryModule } from '../telemetry/telemetry.module';
import { ForumModule } from '../forum/forum.module';
import { AdminForumController } from './admin-forum.controller';
import { ForumModerationService } from './forum-moderation.service';
import { AdminAuditService } from './admin-audit.service';
import { AntiCheatController } from './anti-cheat.controller';
import { AntiCheatService } from './anti-cheat.service';
import { UserModerationService } from './user-moderation.service';
import { AdminManageController } from './admin-manage.controller';
import { CatalogService } from './catalog.service';
import { StatsService } from './stats.service';
import { StudentsService } from './students.service';

/** Web admin (`api/v1/admin/*`): chống gian lận, bản đồ, thống kê, quản lý. Mọi route qua JwtAuthGuard + AdminGuard. */
@Module({
  imports: [TelemetryModule, ForumModule],
  controllers: [AntiCheatController, AdminManageController, AdminForumController],
  providers: [AdminAuditService, AntiCheatService, UserModerationService, StatsService, CatalogService, StudentsService, ForumModerationService],
})
export class AdminModule {}
