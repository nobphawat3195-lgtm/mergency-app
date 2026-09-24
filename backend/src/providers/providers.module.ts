import { Module } from '@nestjs/common';

import { ProvidersService } from './providers.service';
import { ProvidersController } from './providers.controller';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  providers: [ProvidersService],
  controllers: [ProvidersController],
  exports: [ProvidersService],
})
export class ProvidersModule {}
