# FixGo backend (NestJS + Prisma) สำหรับ production
# build: docker build -t fixgo-api ./backend

FROM node:22-bookworm-slim AS build
WORKDIR /app
# Prisma engine ต้องใช้ OpenSSL
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
  && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npx prisma generate \
  && npm run build \
  && npm run build:scripts \
  && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl tini \
  && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production \
    PORT=3000
COPY --from=build --chown=node:node /app/package.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/dist-scripts ./dist-scripts
COPY --from=build --chown=node:node /app/prisma ./prisma
COPY --chown=node:node docker-entrypoint.sh ./
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
ENTRYPOINT ["/usr/bin/tini", "--", "./docker-entrypoint.sh"]
CMD ["node", "dist/main.js"]
