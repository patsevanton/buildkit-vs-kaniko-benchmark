import "reflect-metadata";
import { Controller, Get, Module } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";

@Controller()
export class AppController {
  @Get()
  get(): string {
    return "hello from kaniko-buildkit benchmark (nestjs)\n";
  }
}

@Module({ controllers: [AppController] })
export class AppModule {}

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  await app.listen(3000);
}

void bootstrap();