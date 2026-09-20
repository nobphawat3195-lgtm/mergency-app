import {
  IsArray,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
} from 'class-validator';

export class CreateOrderDto {
  @IsString()
  categoryId!: string;

  @IsString()
  subServiceId!: string;

  @IsString()
  vehicleTypeId!: string;

  @IsLatitude()
  pickupLat!: number;

  @IsLongitude()
  pickupLng!: number;

  @IsOptional()
  @IsString()
  @Length(1, 300)
  pickupAddress?: string;

  @IsOptional()
  @IsString()
  @Length(1, 500)
  note?: string;

  /** รูปปัญหารถที่ลูกค้าแนบมา ช่วยให้ช่างเตรียมอุปกรณ์ก่อนถึงหน้างาน */
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  photoUrls?: string[];
}

export class ProposeQuoteDto {
  /** ราคาที่ช่างเสนอ หน่วยสตางค์ ลูกค้าต้องยืนยันก่อนเริ่มงาน */
  @IsInt()
  @Min(0)
  priceProposed!: number;

  @IsOptional()
  @IsString()
  @Length(1, 500)
  note?: string;
}

export class RateOrderDto {
  @IsInt()
  @Min(1)
  @Max(5)
  score!: number;

  @IsOptional()
  @IsString()
  @Length(1, 500)
  comment?: string;
}
