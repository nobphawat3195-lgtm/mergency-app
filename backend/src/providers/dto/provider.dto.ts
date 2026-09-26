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
  Max,
  Min,
} from 'class-validator';

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

  /** รูปเครื่องมือช่าง ใช้ยืนยันว่าเป็นช่างจริง */
  @IsArray()
  @ArrayNotEmpty()
  @ArrayMaxSize(6)
  @IsString({ each: true })
  toolPhotoUrls!: string[];
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

/** ข้อมูลรับเงิน กรอกหลังได้รับอนุมัติ ก่อนกดเบิกครั้งแรก */
export class UpdatePayoutInfoDto {
  @IsOptional()
  @IsString()
  @Length(1, 80)
  bankName?: string;

  @IsOptional()
  @IsString()
  @Length(1, 120)
  bankAccountName?: string;

  @IsOptional()
  @IsString()
  @Length(1, 30)
  bankAccountNumber?: string;

  @IsOptional()
  @IsString()
  @Length(1, 30)
  promptPayId?: string;
}
