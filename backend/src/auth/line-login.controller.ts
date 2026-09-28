import { Body, Controller, Get, Post, Query, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { IsString, MaxLength } from 'class-validator';

import { isProduction } from '../config/environment';
import { LINE_STATE_COOKIE, LineLoginService } from './line-login.service';

class ExchangeLineTicketDto {
  @IsString()
  @MaxLength(400)
  ticket!: string;
}

function readCookie(request: Request, name: string): string | undefined {
  for (const part of (request.headers.cookie ?? '').split(';')) {
    const [key, ...rest] = part.trim().split('=');
    if (key === name) return decodeURIComponent(rest.join('='));
  }
  return undefined;
}

@Controller('auth/line')
export class LineLoginController {
  constructor(private readonly line: LineLoginService) {}

  /** เว็บลูกค้าถามก่อนว่าจะแสดงปุ่ม "เข้าสู่ระบบด้วย LINE" ไหม */
  @Get('config')
  config() {
    return { enabled: this.line.isEnabled() };
  }

  @Get('start')
  start(@Res() res: Response) {
    const { url, cookie, maxAgeSeconds } = this.line.start();
    res.cookie(LINE_STATE_COOKIE, cookie, {
      httpOnly: true,
      secure: isProduction(),
      sameSite: 'lax',
      path: '/api/auth/line',
      maxAge: maxAgeSeconds * 1000,
    });
    res.redirect(302, url);
  }

  @Get('callback')
  async callback(
    @Query() query: { code?: string; state?: string; error?: string },
    @Req() req: Request,
    @Res() res: Response,
  ) {
    res.clearCookie(LINE_STATE_COOKIE, { path: '/api/auth/line' });
    try {
      const target = await this.line.callback(
        query,
        readCookie(req, LINE_STATE_COOKIE),
      );
      res.redirect(302, target);
    } catch {
      res.redirect(302, this.line.failureRedirect());
    }
  }

  @Post('exchange')
  exchange(@Body() dto: ExchangeLineTicketDto) {
    return this.line.exchange(dto.ticket);
  }
}
