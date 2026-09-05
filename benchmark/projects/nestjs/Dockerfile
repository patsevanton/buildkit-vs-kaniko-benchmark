# Multi-stage Dockerfile — проект nestjs (Node/TS, тяжёлый npm ci + декораторы).
FROM node:22-bookworm-slim AS builder
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc --project tsconfig.json

FROM node:22-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=builder /src/node_modules ./node_modules
COPY --from=builder /src/dist ./dist
EXPOSE 3000
CMD ["node", "dist/main.js"]