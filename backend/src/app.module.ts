import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';

import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { CatalogModule } from './catalog/catalog.module';
import { ProvidersModule } from './providers/providers.module';
import { OrdersModule } from './orders/orders.module';
import { DispatchModule } from './dispatch/dispatch.module';
import { WalletModule } from './wallet/wallet.module';
import { PaymentsModule } from './payments/payments.module';
import { AdminModule } from './admin/admin.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    CatalogModule,
    ProvidersModule,
    OrdersModule,
    DispatchModule,
    WalletModule,
    PaymentsModule,
    AdminModule,
  ],
})
export class AppModule {}
