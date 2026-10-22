import { Module } from '@nestjs/common';
import { TurfGateway } from './turf.gateway';

@Module({
  providers: [TurfGateway],
  exports: [TurfGateway],
})
export class RealtimeModule {}
