import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';

import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './jwt.strategy';
import { NotificationsModule } from '../notifications/notifications.module';
import { readSecret } from '../config/environment';

@Module({
  imports: [
    NotificationsModule,
    PassportModule,
    JwtModule.registerAsync({
      useFactory: () => ({
        secret: readSecret('JWT_SECRET', 'dev-jwt-secret'),
        signOptions: {
          expiresIn: Number(process.env.JWT_EXPIRES_SECONDS ?? 2_592_000),
        },
      }),
    }),
  ],
  providers: [AuthService, JwtStrategy],
  controllers: [AuthController],
  exports: [AuthService],
})
export class AuthModule {}
