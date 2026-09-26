import { Module } from '@nestjs/common';

import { InspectionsController } from './inspections.controller';
import { InspectionsService } from './inspections.service';

@Module({
  providers: [InspectionsService],
  controllers: [InspectionsController],
  exports: [InspectionsService],
})
export class InspectionsModule {}
