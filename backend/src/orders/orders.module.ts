import { Module } from '@nestjs/common';

import { OrdersService } from './orders.service';
import { OrdersController } from './orders.controller';
import { OrderShareService } from './order-share.service';
import { PublicTrackingController } from './public-tracking.controller';
import { CatalogModule } from '../catalog/catalog.module';
import { DispatchModule } from '../dispatch/dispatch.module';
import { InspectionsModule } from '../inspections/inspections.module';

@Module({
  imports: [CatalogModule, DispatchModule, InspectionsModule],
  providers: [OrdersService, OrderShareService],
  controllers: [OrdersController, PublicTrackingController],
  exports: [OrdersService],
})
export class OrdersModule {}
