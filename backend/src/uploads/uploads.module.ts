import { Global, Module } from '@nestjs/common';

import { LocalUploadsController } from './local-uploads.controller';
import { UploadsController } from './uploads.controller';
import { UploadsService } from './uploads.service';

@Global()
@Module({
  controllers: [UploadsController, LocalUploadsController],
  providers: [UploadsService],
  exports: [UploadsService],
})
export class UploadsModule {}
