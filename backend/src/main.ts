import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors({
    origin: '*',
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  app.useGlobalFilters(new AllExceptionsFilter());

  // OpenAPI Swagger 3.0 Documentation Setup
  const config = new DocumentBuilder()
    .setTitle('SISO API Platform')
    .setDescription(
      'Hệ thống API & WebSocket cho Ứng dụng Gamified Running Chiếm Lãnh Thổ Liên Trường (Step In Step Out)',
    )
    .setVersion('2.0')
    .addBearerAuth()
    .addTag('Auth', 'Xác thực sinh viên bằng Email Edu (@*.edu.vn)')
    .addTag('Telemetry', 'Kiểm định Anti-GIGO (Kinematic & Biometric FFT)')
    .addTag('Turf', 'Bản đồ lục giác H3 & Chiếm đất khép vòng')
    .addTag('Leaderboard', 'Bộ đếm song song: % Đất & % Km Toàn cầu')
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('docs', app, document);

  const port = process.env.PORT || 3000;
  await app.listen(port);
  console.log(`🚀 SISO API Server is running on: http://localhost:${port}`);
  console.log(`📚 Swagger Documentation is available at: http://localhost:${port}/docs`);
}
bootstrap();
