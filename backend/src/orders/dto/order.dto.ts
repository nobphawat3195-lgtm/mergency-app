import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
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

/** รูปตอนปิดงาน (อัปโหลดผ่าน /uploads/presign scope ORDER ด้วยบัญชีช่างเอง) */
export class CompleteOrderDto {
  @IsArray({ message: 'กรุณาแนบรูปรถหลังซ่อมเสร็จอย่างน้อย 1 รูป' })
  @ArrayMinSize(1, { message: 'กรุณาแนบรูปรถหลังซ่อมเสร็จอย่างน้อย 1 รูป' })
  @ArrayMaxSize(5, { message: 'แนบรูปรถได้สูงสุด 5 รูป' })
  @IsString({ each: true })
  carPhotoUrls!: string[];

  /** ใบเสร็จค่าอะไหล่หรือสลิป ไม่บังคับ */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(3, { message: 'แนบใบเสร็จได้สูงสุด 3 รูป' })
  @IsString({ each: true })
  receiptPhotoUrls?: string[];
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
