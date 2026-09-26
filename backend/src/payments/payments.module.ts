import { Module } from '@nestjs/common';

import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { WalletModule } from '../wallet/wallet.module';
import { createPaymentGateway, PAYMENT_GATEWAY } from './payment-gateway';

@Module({
  imports: [WalletModule],
  providers: [
    PaymentsService,
    { provide: PAYMENT_GATEWAY, useFactory: createPaymentGateway },
  ],
  controllers: [PaymentsController],
  exports: [PaymentsService],
})
export class PaymentsModule {}
