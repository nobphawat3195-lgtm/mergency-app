import { IsOptional, IsString, MaxLength } from 'class-validator';

export class SendOrderMessageDto {
  @IsOptional()
  @IsString({ message: 'ข้อความไม่ถูกต้อง' })
  @MaxLength(1000, { message: 'ข้อความยาวเกิน 1,000 ตัวอักษร' })
  text?: string;

  /** รูปที่อัปโหลดผ่าน /uploads/presign (scope ORDER) ของผู้ส่งเอง */
  @IsOptional()
  @IsString({ message: 'ลิงก์รูปไม่ถูกต้อง' })
  @MaxLength(500)
  imageUrl?: string;
}

export class ReportOrderChatDto {
  @IsString({ message: 'กรุณาบอกเหตุผลที่รายงาน' })
  @MaxLength(500, { message: 'เหตุผลยาวเกิน 500 ตัวอักษร' })
  reason!: string;
}
