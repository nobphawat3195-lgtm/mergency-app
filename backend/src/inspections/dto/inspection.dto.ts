import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsDateString,
  IsEnum,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUrl,
  Length,
  Matches,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { InspectionItemStatus } from '@prisma/client';

/** ข้อมูลที่ลูกค้ากรอกตอนจองตรวจรถมือสอง */
export class InspectionBookingDto {
  @IsOptional()
  @IsString()
  @Length(1, 60)
  brand?: string;

  @IsOptional()
  @IsString()
  @Length(1, 80)
  model?: string;

  @IsOptional()
  @IsInt()
  @Min(1970)
  @Max(2100)
  year?: number;

  @IsOptional()
  @IsUrl({ require_protocol: true })
  @Length(1, 500)
  listingUrl?: string;

  @IsOptional()
  @IsString()
  @Length(1, 80)
  sellerName?: string;

  @IsOptional()
  @Matches(/^0\d{8,9}$/, { message: 'เบอร์ผู้ขายต้องเป็นเบอร์ไทย 9-10 หลัก' })
  sellerPhone?: string;

  @IsOptional()
  @IsDateString()
  appointmentAt?: string;
}

export class InspectionItemDto {
  @IsString()
  @Length(2, 10)
  itemCode!: string;

  @IsOptional()
  @IsEnum(InspectionItemStatus)
  status?: InspectionItemStatus | null;

  @IsOptional()
  @IsNumber()
  measurement?: number | null;

  @IsOptional()
  @IsString()
  @Length(0, 500)
  note?: string | null;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(5)
  @IsString({ each: true })
  photoUrls?: string[];
}

export class InspectionPhotoDto {
  // URL จาก /uploads/presign (ตอน dev เป็น localhost ซึ่ง IsUrl ไม่รับ) ใช้แบบเดียวกับ photoUrls
  @IsString()
  @Length(1, 1000)
  url!: string;

  @IsOptional()
  @IsString()
  @Length(0, 200)
  caption?: string | null;
}

/** รูปทั้งหมดของ 1 ช่อง ส่งมาแทนที่ของเดิมทั้งช่อง (ลบรูป = ส่งรายการที่เหลือ) */
export class InspectionPhotoSlotDto {
  @IsString()
  @Length(2, 20)
  slotCode!: string;

  @IsArray()
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => InspectionPhotoDto)
  photos!: InspectionPhotoDto[];
}

/** ช่างบันทึกข้อมูลรถและผลตรวจทีละส่วน (autosave) */
export class UpdateInspectionDto {
  @IsOptional()
  @IsString()
  @Length(1, 60)
  brand?: string;

  @IsOptional()
  @IsString()
  @Length(1, 80)
  model?: string;

  @IsOptional()
  @IsInt()
  @Min(1970)
  @Max(2100)
  year?: number;

  @IsOptional()
  @IsString()
  @Length(1, 40)
  color?: string;

  @IsOptional()
  @IsString()
  @Length(1, 20)
  plateNo?: string;

  @IsOptional()
  @IsString()
  @Length(1, 40)
  plateProvince?: string;

  @IsOptional()
  @IsString()
  @Length(5, 30)
  vin?: string;

  @IsOptional()
  @IsString()
  @Length(1, 30)
  engineNo?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(2_000_000)
  mileageKm?: number;

  @IsOptional()
  @IsIn(['combustion', 'electrified', 'hybrid'])
  powertrain?: 'combustion' | 'electrified' | 'hybrid';

  @IsOptional()
  @IsIn(['manual', 'automatic'])
  transmission?: 'manual' | 'automatic';

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  summary?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => InspectionItemDto)
  items?: InspectionItemDto[];

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(40)
  @ValidateNested({ each: true })
  @Type(() => InspectionPhotoSlotDto)
  photoSlots?: InspectionPhotoSlotDto[];
}
