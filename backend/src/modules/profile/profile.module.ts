import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ProfileController } from './profile.controller';
import { ProfileService } from './profile.service';
import { User } from '../../entities/user.entity';
import { UserAvatar } from '../../entities/user-avatar.entity';
import { RunningSession } from '../../entities/running-session.entity';

@Module({
  imports: [TypeOrmModule.forFeature([User, UserAvatar, RunningSession])],
  controllers: [ProfileController],
  providers: [ProfileService],
})
export class ProfileModule {}
