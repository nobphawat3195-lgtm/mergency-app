import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';

import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { CatalogModule } from './catalog/catalog.module';
import { ProvidersModule } from './providers/providers.module';
import { OrdersModule } from './orders/orders.module';
import { DispatchModule } from './dispatch/dispatch.module';
import { WalletModule } from './wallet/wallet.module';
import { UploadsModule } from './uploads/uploads.module';
import { PaymentsModule } from './payments/payments.module';
import { AdminModule } from './admin/admin.module';
import { HealthModule } from './health/health.module';
import { InspectionsModule } from './inspections/inspections.module';
import { AccountModule } from './account/account.module';
import { LegalModule } from './legal/legal.module';

@Module({
  imports: [
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    CatalogModule,
    ProvidersModule,
    OrdersModule,
    DispatchModule,
    WalletModule,
    UploadsModule,
    PaymentsModule,
    AdminModule,
    HealthModule,
    InspectionsModule,
    AccountModule,
    LegalModule,
  ],
})
export class AppModule {}
