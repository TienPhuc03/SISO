import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from './modules/auth/auth.module';
import { TelemetryModule } from './modules/telemetry/telemetry.module';
import { TurfModule } from './modules/turf/turf.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { LeaderboardModule } from './modules/leaderboard/leaderboard.module';

import { University } from './entities/university.entity';
import { User } from './entities/user.entity';
import { H3Hexagon } from './entities/h3-hexagon.entity';
import { Arena } from './entities/arena.entity';
import { RunningSession } from './entities/running-session.entity';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
    }),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => {
        const isSsl = configService.get<string>('DB_SSL', 'false') === 'true';
        const databaseUrl = configService.get<string>('DATABASE_URL');

        return {
          type: 'postgres',
          ...(databaseUrl
            ? { url: databaseUrl }
            : {
                host: configService.get<string>('DB_HOST', 'localhost'),
                port: configService.get<number>('DB_PORT', 5432),
                username: configService.get<string>('DB_USER'),
                password: configService.get<string>('DB_PASSWORD'),
                database: configService.get<string>('DB_NAME'),
              }),
          entities: [University, User, H3Hexagon, Arena, RunningSession],
          synchronize: false,
          logging: configService.get<string>('NODE_ENV') === 'development',
          ssl: isSsl ? { rejectUnauthorized: false } : false,
        };
      },
      inject: [ConfigService],
    }),
    AuthModule,
    TelemetryModule,
    TurfModule,
    RealtimeModule,
    LeaderboardModule,
  ],
})
export class AppModule {}
