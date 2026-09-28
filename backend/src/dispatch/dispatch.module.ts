import { Module } from '@nestjs/common';

import { DispatchService } from './dispatch.service';
import { DispatchController } from './dispatch.controller';
import { WalletModule } from '../wallet/wallet.module';

@Module({
  imports: [WalletModule],
  providers: [DispatchService],
  controllers: [DispatchController],
  exports: [DispatchService],
})
export class DispatchModule {}
