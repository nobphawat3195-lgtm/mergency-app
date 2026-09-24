import { IsIn, IsInt, IsString, Max, MaxLength, Min } from 'class-validator';

export class PresignUploadDto {
  @IsString()
  @MaxLength(180)
  fileName!: string;

  @IsIn(['image/jpeg', 'image/png', 'image/webp'])
  contentType!: 'image/jpeg' | 'image/png' | 'image/webp';

  @IsInt()
  @Min(1)
  @Max(10 * 1024 * 1024)
  byteLength!: number;

  @IsIn(['ORDER', 'PROVIDER_TOOL', 'INSPECTION'])
  scope!: 'ORDER' | 'PROVIDER_TOOL' | 'INSPECTION';
}
