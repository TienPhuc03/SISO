import { Module } from '@nestjs/common';
import { TelemetryController } from './telemetry.controller';
import { TelemetryService } from './telemetry.service';
import { AntiGigoService } from './anti-gigo.service';

@Module({
  controllers: [TelemetryController],
  providers: [TelemetryService, AntiGigoService],
  exports: [TelemetryService, AntiGigoService],
})
export class TelemetryModule {}
