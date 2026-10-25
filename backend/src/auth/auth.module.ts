import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';

import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { AppleLoginController } from './apple-login.controller';
import { AppleLoginService } from './apple-login.service';
import { JwtStrategy } from './jwt.strategy';
import { LineLoginController } from './line-login.controller';
import { LineLoginService } from './line-login.service';
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
  providers: [AuthService, JwtStrategy, LineLoginService, AppleLoginService],
  controllers: [AuthController, LineLoginController, AppleLoginController],
  exports: [AuthService, AppleLoginService],
})
export class AuthModule {}
