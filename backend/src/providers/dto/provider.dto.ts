import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsBoolean,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

import { Transform } from 'class-transformer';

import { THAI_PHONE } from '../../auth/dto/auth.dto';

/** แบบฟอร์มลงทะเบียนช่าง — ฟิลด์ตรงกับฟอร์มจริงที่ใช้คัดกรองช่าง */
export class RegisterProviderDto {
  @IsString()
  @Length(1, 120)
  realName!: string;

  @IsString()
  @Length(1, 60)
  nickname!: string;

  @IsInt()
  @Min(0)
  @Max(60)
  experienceYears!: number;

  @IsOptional()
  @IsString()
  @Length(1, 160)
  shopName?: string;

  @IsOptional()
  @IsString()
  @Length(1, 300)
  facebookPage?: string;

  @IsLatitude()
  baseLat!: number;

  @IsLongitude()
  baseLng!: number;

  /** เวลาเปิด-ปิด เป็นนาทีนับจากเที่ยงคืน เช่น 08:00 = 480 */
  @IsInt()
  @Min(0)
  @Max(1439)
  openMinute!: number;

  @IsInt()
  @Min(0)
  @Max(1439)
  closeMinute!: number;

  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  categoryIds!: string[];

  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  vehicleTypeIds!: string[];

  /** รูปเครื่องมือช่าง ไม่บังคับ ช่วยให้ทีมงานอนุมัติได้เร็วขึ้น */
  @IsArray()
  @ArrayMaxSize(6)
  @IsString({ each: true })
  toolPhotoUrls!: string[];

  /** รูปหน้าตรงของช่าง ทีมงานใช้ตรวจตัวตน และลูกค้าเห็นในการ์ดช่าง */
  @IsString()
  @Length(1, 500)
  photoUrl!: string;

  /** ทะเบียนรถที่ใช้ไปหน้างาน ลูกค้าใช้ยืนยันว่าเป็นช่างตัวจริง */
  @IsString()
  @Length(2, 20)
  vehiclePlate!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  vehicleDesc?: string;

  /**
   * เบอร์ติดต่อของช่าง ใช้เฉพาะคนที่สมัครผ่าน LINE (ยังไม่มีเบอร์ที่ยืนยันด้วย OTP)
   * ช่างที่ล็อกอินด้วยเบอร์โทรใช้เบอร์จากโทเคนเสมอ ค่านี้จะถูกเมิน
   */
  @IsOptional()
  @Matches(THAI_PHONE, { message: 'เบอร์โทรศัพท์ไม่ถูกต้อง' })
  phone?: string;
}

export class UpdateLocationDto {
  @IsLatitude()
  lat!: number;

  @IsLongitude()
  lng!: number;
}

export class SetOnlineDto {
  @IsBoolean()
  isOnline!: boolean;
}

/** ช่องที่เว้นว่างหรือมีแต่ช่องว่างถือว่าลบค่านั้น (null) */
const blankToNull = ({ value }: { value: unknown }) => {
  if (typeof value !== 'string') return value;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
};

/**
 * ข้อมูลรับเงิน กรอกหลังได้รับอนุมัติ ก่อนกดเบิกครั้งแรก
 * ช่องที่ไม่ส่งมาคงค่าเดิม ช่องที่ส่ง null หรือค่าว่างคือลบ
 * หลังบันทึกต้องมีบัญชีธนาคารครบ (ธนาคาร+ชื่อบัญชี+เลขบัญชี) หรือพร้อมเพย์ อย่างใดอย่างหนึ่ง
 */
export class UpdatePayoutInfoDto {
  @IsOptional()
  @Transform(blankToNull)
  @IsString({ message: 'ชื่อธนาคารไม่ถูกต้อง' })
  @MaxLength(80, { message: 'ชื่อธนาคารยาวเกิน 80 ตัวอักษร' })
  bankName?: string | null;

  @IsOptional()
  @Transform(blankToNull)
  @IsString({ message: 'ชื่อบัญชีไม่ถูกต้อง' })
  @MaxLength(120, { message: 'ชื่อบัญชียาวเกิน 120 ตัวอักษร' })
  bankAccountName?: string | null;

  @IsOptional()
  @Transform(blankToNull)
  @IsString({ message: 'เลขบัญชีไม่ถูกต้อง' })
  @MaxLength(30, { message: 'เลขบัญชียาวเกิน 30 ตัวอักษร' })
  bankAccountNumber?: string | null;

  @IsOptional()
  @Transform(blankToNull)
  @IsString({ message: 'เลขพร้อมเพย์ไม่ถูกต้อง' })
  @MaxLength(30, { message: 'เลขพร้อมเพย์ยาวเกิน 30 ตัวอักษร' })
  promptPayId?: string | null;
}

/**
 * ข้อมูลที่ลูกค้าเห็นในการ์ดช่างหลังรับงาน ส่งค่าว่าง ("") เพื่อลบ
 * รูปต้องเป็นไฟล์ที่ช่างคนนี้อัปโหลดเอง (scope PROVIDER_TOOL)
 */
export class UpdatePublicProfileDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  photoUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  vehicleDesc?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  vehiclePlate?: string;
}
