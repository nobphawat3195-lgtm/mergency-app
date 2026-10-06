import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

import { InspectionBookingDto } from '../../inspections/dto/inspection.dto';

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
  @ArrayMaxSize(5)
  @IsString({ each: true })
  photoUrls?: string[];

  /** ข้อมูลนัดตรวจรถมือสอง ใช้เฉพาะหมวดตรวจรถ */
  @IsOptional()
  @ValidateNested()
  @Type(() => InspectionBookingDto)
  inspection?: InspectionBookingDto;
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

/** ตัวเลือกด่วนของคำถาม "อยากให้ FixGo เพิ่มบริการหรือปรับอะไร" (แอปแสดงเป็นภาษาไทย) */
export const SUGGESTION_CHOICES = [
  'TOW_TRUCK',
  'FASTER_ARRIVAL',
  'LOWER_PRICE',
  'MORE_AREAS',
  'OTHER',
] as const;

export class ServiceSuggestionDto {
  @IsArray()
  @ArrayMaxSize(SUGGESTION_CHOICES.length)
  @ArrayUnique()
  @IsIn(SUGGESTION_CHOICES, { each: true, message: 'ตัวเลือกไม่ถูกต้อง' })
  choices!: string[];

  @IsOptional()
  @IsString()
  @Length(1, 300, { message: 'ข้อความยาวได้ไม่เกิน 300 ตัวอักษร' })
  otherText?: string;
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

/** The exact quote displayed to the customer, not whatever happens to be current. */
export class RespondQuoteDto {
  @IsInt()
  @Min(0)
  quoteVersion!: number;

  @IsInt()
  @Min(0)
  priceProposed!: number;
}
