import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

import { JwtPayload } from './auth.service';
import { readSecret } from '../config/environment';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: readSecret('JWT_SECRET', 'dev-jwt-secret'),
    });
  }

  validate(payload: JwtPayload): JwtPayload {
    return payload;
  }
}
