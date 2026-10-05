import {
  Body,
  Controller,
  Get,
  Logger,
  Post,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { IsString, MaxLength } from 'class-validator';

import { isProduction } from '../config/environment';
import {
  LINE_STATE_COOKIE,
  LineLoginService,
  parseLineApp,
} from './line-login.service';

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
  private readonly logger = new Logger(LineLoginController.name);

  constructor(private readonly line: LineLoginService) {}

  /** เว็บถามก่อนว่าจะแสดงปุ่ม "เข้าสู่ระบบด้วย LINE" ไหม (?app=provider สำหรับแอปช่าง) */
  @Get('config')
  config(@Query('app') app?: string) {
    return { enabled: this.line.isEnabled(parseLineApp(app)) };
  }

  @Get('start')
  start(@Query('app') app: string | undefined, @Res() res: Response) {
    const { url, cookie, maxAgeSeconds } = this.line.start(parseLineApp(app));
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
    const cookie = readCookie(req, LINE_STATE_COOKIE);
    try {
      const target = await this.line.callback(query, cookie);
      res.redirect(302, target);
    } catch (error) {
      const app = this.line.failureApp(query.state, cookie);
      // บอกแค่เหตุผล ห้าม log code/token/state/secret
      const reason = error instanceof Error ? error.message : String(error);
      this.logger.warn(
        `LINE login failed (app=${app}, cookie=${cookie ? 'yes' : 'no'}` +
          `${query.error ? `, line_error=${query.error.slice(0, 40)}` : ''}): ${reason}`,
      );
      res.redirect(302, this.line.failureRedirect(app));
    }
  }

  @Post('exchange')
  exchange(@Body() dto: ExchangeLineTicketDto) {
    return this.line.exchange(dto.ticket);
  }
}
