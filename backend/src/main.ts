import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import {
  allowedCorsOrigins,
  validateEnvironment,
} from './config/environment';

async function bootstrap() {
  validateEnvironment(process.env);
  const app = await NestFactory.create(AppModule);

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.setGlobalPrefix('api');
  const corsOrigins = allowedCorsOrigins();
  app.enableCors({
    origin: corsOrigins === true ? true : corsOrigins,
    credentials: corsOrigins !== true,
  });

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
}

void bootstrap();
