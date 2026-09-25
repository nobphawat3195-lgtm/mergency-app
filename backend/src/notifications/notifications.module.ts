import { Global, Module } from '@nestjs/common';

import { AdminAlertService } from './admin-alert.service';
import { DevicesController } from './devices.controller';
import { OrderEventsService } from './order-events.service';
import { createPushSender, PUSH_SENDER } from './push-sender';
import { PushService } from './push.service';
import { SmsService } from './sms.service';

@Global()
@Module({
  providers: [
    SmsService,
    PushService,
    OrderEventsService,
    { provide: AdminAlertService, useFactory: () => new AdminAlertService() },
    { provide: PUSH_SENDER, useFactory: () => createPushSender() },
  ],
  controllers: [DevicesController],
  exports: [SmsService, PushService, AdminAlertService, OrderEventsService],
})
export class NotificationsModule {}
