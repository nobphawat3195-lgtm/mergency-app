import { Module } from '@nestjs/common';

import { OrdersService } from './orders.service';
import { OrdersController } from './orders.controller';
import { OrderShareService } from './order-share.service';
import { OrderChatService } from './order-chat.service';
import { OrderChatController } from './order-chat.controller';
import { PublicTrackingController } from './public-tracking.controller';
import { CatalogModule } from '../catalog/catalog.module';
import { DispatchModule } from '../dispatch/dispatch.module';
import { InspectionsModule } from '../inspections/inspections.module';

@Module({
  imports: [CatalogModule, DispatchModule, InspectionsModule],
  providers: [OrdersService, OrderShareService, OrderChatService],
  controllers: [
    OrdersController,
    OrderChatController,
    PublicTrackingController,
  ],
  exports: [OrdersService, OrderChatService],
})
export class OrdersModule {}
