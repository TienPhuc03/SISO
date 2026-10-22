import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TurfController } from './turf.controller';
import { TurfService } from './turf.service';
import { H3Service } from './h3.service';
import { H3Hexagon } from '../../entities/h3-hexagon.entity';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { RunningSession } from '../../entities/running-session.entity';
import { RealtimeModule } from '../realtime/realtime.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([H3Hexagon, University, User, RunningSession]),
    RealtimeModule,
  ],
  controllers: [TurfController],
  providers: [TurfService, H3Service],
  exports: [TurfService, H3Service],
})
export class TurfModule {}
