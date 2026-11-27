import { Module } from '@nestjs/common';
import { ForumController } from './forum.controller';
import { ForumImageStore } from './forum-image.store';
import { ForumService } from './forum.service';

@Module({
  controllers: [ForumController],
  providers: [ForumService, ForumImageStore],
  exports: [ForumService, ForumImageStore],
})
export class ForumModule {}
