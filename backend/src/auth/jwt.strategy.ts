import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

import { AccountService } from '../account/account.service';
import { JwtPayload } from './auth.service';
import { readSecret } from '../config/environment';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly account: AccountService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: readSecret('JWT_SECRET', 'dev-jwt-secret'),
    });
  }

  async validate(payload: JwtPayload): Promise<JwtPayload> {
    // โทเคนของบัญชีที่ลบแล้วต้องใช้ต่อไม่ได้ทันที แม้ยังไม่หมดอายุ
    if (!(await this.account.isActive(payload.sub, payload.role))) {
      throw new UnauthorizedException('บัญชีนี้ถูกลบแล้ว');
    }
    return payload;
  }
}
