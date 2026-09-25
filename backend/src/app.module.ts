import { Module } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { SentryGlobalFilter, SentryModule } from '@sentry/nestjs/setup';

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
import { NotificationsModule } from './notifications/notifications.module';

@Module({
  imports: [
    // ส่งเฉพาะ error ที่ไม่ใช่ HttpException (เช่น 500) ไป Sentry ถ้าตั้ง SENTRY_DSN
    SentryModule.forRoot(),
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
    NotificationsModule,
  ],
  providers: [{ provide: APP_FILTER, useClass: SentryGlobalFilter }],
})
export class AppModule {}
