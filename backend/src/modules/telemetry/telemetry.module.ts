import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TelemetryController } from './telemetry.controller';
import { TelemetryService } from './telemetry.service';
import { AntiGigoService } from './anti-gigo.service';
import { RunningSession } from '../../entities/running-session.entity';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';

@Module({
  imports: [TypeOrmModule.forFeature([RunningSession, GigoAuditLog])],
  controllers: [TelemetryController],
  providers: [TelemetryService, AntiGigoService],
  exports: [TelemetryService, AntiGigoService],
})
export class TelemetryModule {}
