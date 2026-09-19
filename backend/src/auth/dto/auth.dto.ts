import { IsEnum, IsString, Length, Matches } from 'class-validator';
import { Role } from '@prisma/client';

const THAI_PHONE = /^0[0-9]{8,9}$/;

export class RequestOtpDto {
  @Matches(THAI_PHONE, { message: 'เบอร์โทรศัพท์ไม่ถูกต้อง' })
  phone!: string;

  @IsEnum(Role)
  role!: Role;
}

export class VerifyOtpDto {
  @Matches(THAI_PHONE, { message: 'เบอร์โทรศัพท์ไม่ถูกต้อง' })
  phone!: string;

  @IsEnum(Role)
  role!: Role;

  @IsString()
  @Length(6, 6)
  code!: string;
}
