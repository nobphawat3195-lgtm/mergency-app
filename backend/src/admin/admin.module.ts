import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';

import { AdminService } from './admin.service';
import { AdminController } from './admin.controller';
import { WalletModule } from '../wallet/wallet.module';
import { DispatchModule } from '../dispatch/dispatch.module';
import { PaymentsModule } from '../payments/payments.module';

@Module({
  imports: [
    WalletModule,
    DispatchModule,
    PaymentsModule,
    JwtModule.register({
      secret: process.env.JWT_SECRET ?? 'dev-jwt-secret',
      signOptions: {
        expiresIn: Number(process.env.JWT_EXPIRES_SECONDS ?? 2_592_000),
      },
    }),
  ],
  providers: [AdminService],
  controllers: [AdminController],
})
export class AdminModule {}
