# Multi-stage Dockerfile — проект nextjs (Node/React SSR: npm ci + сборка клиента).
FROM node:22-bookworm-slim AS builder
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY next.config.js ./
COPY src ./src
RUN npm run build

FROM node:22-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=builder /src/node_modules ./node_modules
COPY --from=builder /src/.next ./.next
COPY --from=builder /src/package.json ./package.json
EXPOSE 3000
CMD ["node_modules/.bin/next", "start"]