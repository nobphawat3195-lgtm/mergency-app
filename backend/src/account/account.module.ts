import { Global, Module } from '@nestjs/common';

import { WalletModule } from '../wallet/wallet.module';
import { AccountController } from './account.controller';
import { AccountService } from './account.service';

@Global()
@Module({
  imports: [WalletModule],
  providers: [AccountService],
  controllers: [AccountController],
  exports: [AccountService],
})
export class AccountModule {}
