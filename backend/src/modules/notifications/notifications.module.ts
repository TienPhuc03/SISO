import { Module } from '@nestjs/common';
import { PushService } from './push.service';
import { PatrolReminderService } from './patrol-reminder.service';

@Module({
  providers: [PushService, PatrolReminderService],
  exports: [PushService],
})
export class NotificationsModule {}
