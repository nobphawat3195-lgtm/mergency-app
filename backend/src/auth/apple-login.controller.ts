import { Body, Controller, Post } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

import { AppleLoginService, parseAppleApp } from './apple-login.service';

class AppleSignInDto {
  @IsIn(['customer', 'provider'])
  app!: string;

  @IsString()
  @MaxLength(4000)
  identityToken!: string;

  @IsString()
  @MaxLength(200)
  nonce!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  authorizationCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  fullName?: string;
}

@Controller('auth/apple')
export class AppleLoginController {
  constructor(private readonly apple: AppleLoginService) {}

  /** แอป iPhone ส่ง identity token จาก Sign in with Apple มาแลก accessToken */
  @Post()
  signIn(@Body() dto: AppleSignInDto) {
    return this.apple.signIn({
      app: parseAppleApp(dto.app),
      identityToken: dto.identityToken,
      nonce: dto.nonce,
      authorizationCode: dto.authorizationCode,
      fullName: dto.fullName,
    });
  }
}
