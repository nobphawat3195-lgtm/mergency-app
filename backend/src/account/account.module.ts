import { Global, Module } from '@nestjs/common';

import { WalletModule } from '../wallet/wallet.module';
import { AccountController } from './account.controller';
import { AccountService } from './account.service';
import { AppleTokenService } from '../auth/apple-token.service';

@Global()
@Module({
  imports: [WalletModule],
  providers: [AccountService, AppleTokenService],
  controllers: [AccountController],
  exports: [AccountService, AppleTokenService],
})
export class AccountModule {}
