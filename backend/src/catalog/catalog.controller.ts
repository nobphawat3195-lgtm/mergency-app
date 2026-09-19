import { Controller, Get, Param, Query } from '@nestjs/common';

import { CatalogService } from './catalog.service';

@Controller('catalog')
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  @Get('categories')
  listCategories() {
    return this.catalog.listCategories();
  }

  @Get('categories/:id/sub-services')
  listSubServices(@Param('id') id: string) {
    return this.catalog.listSubServices(id);
  }

  @Get('vehicle-types')
  listVehicleTypes() {
    return this.catalog.listVehicleTypes();
  }

  @Get('quote')
  quote(
    @Query('subServiceId') subServiceId: string,
    @Query('vehicleTypeId') vehicleTypeId: string,
  ) {
    return this.catalog.quote(subServiceId, vehicleTypeId);
  }
}
