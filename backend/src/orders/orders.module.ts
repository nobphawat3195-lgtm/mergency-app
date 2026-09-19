import { Module } from '@nestjs/common';

import { OrdersService } from './orders.service';
import { OrdersController } from './orders.controller';
import { CatalogModule } from '../catalog/catalog.module';
import { DispatchModule } from '../dispatch/dispatch.module';

@Module({
  imports: [CatalogModule, DispatchModule],
  providers: [OrdersService],
  controllers: [OrdersController],
  exports: [OrdersService],
})
export class OrdersModule {}
