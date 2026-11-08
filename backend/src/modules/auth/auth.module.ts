import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';

import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './jwt.strategy';
import { MailService } from './mail/mail.service';
import { InMemoryOtpStore, OTP_STORE } from './otp/otp-store';
import { AUTH_THROTTLE_ERROR, AUTH_THROTTLE_TTL_MS } from './auth-throttle';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([User, University]),
    // Giới hạn request theo IP cho Auth (chống spam gửi OTP); limit cụ thể đặt ở từng route
    ThrottlerModule.forRoot({
      throttlers: [{ name: 'default', ttl: AUTH_THROTTLE_TTL_MS, limit: 30 }],
      errorMessage: AUTH_THROTTLE_ERROR,
    }),
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.registerAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        signOptions: { expiresIn: config.get<string>('JWT_EXPIRES_IN', '7d') },
      }),
      inject: [ConfigService],
    }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    JwtStrategy,
    MailService,
    { provide: OTP_STORE, useClass: InMemoryOtpStore },
  ],
  exports: [AuthService, JwtStrategy, PassportModule],
})
export class AuthModule {}
