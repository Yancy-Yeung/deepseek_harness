# syntax=docker/dockerfile:1.7

# ---------- build stage ----------
FROM node:22-slim AS builder

ENV PNPM_HOME="/pnpm" \
    PATH="$PNPM_HOME:$PATH"

RUN corepack enable pnpm && \
    mkdir -p /etc/pip.conf && echo "" > /etc/pip.conf  # silence pip warnings on slim images

WORKDIR /app

# cache node_modules via pnpm store (monorepo-friendly)
COPY --link pnpm-workspace.yaml package.json ./
RUN corepack enable pnpm \
    && mkdir -p ~/.pnpm-store \
    && echo "storeDir: ~/.pnpm-store" > .npmrc \
    # install with frozen lockfile first for cache layering; devDeps excluded in prod build below (none exist)
    && pnpm config set store-dir ~/.pnpm-store \
    && pnpm fetch --prod

# vendor/ packages are pinned copies — copy before source so they don't bust the dep-cache on every edit.
COPY --link vendor/ ./vendor/

# copy package.json files (workspace roots) and source in one layer for cache efficiency
COPY --link tsconfig*.json .npmrc* pnpm-lock.yaml ./
COPY --link packages/*/package.json packages/group/*/package.json 2>/dev/null || true
COPY --link apps/cli/package.json apps/web/package.json 2>/dev/null || true

# copy source (excludes node_modules via .dockerignore)
COPY --link packages/ ./packages/
COPY --link native/     ./native/
COPY --link python/     ./python/

RUN corepack enable pnpm \
    && PUPPETEER_SKIP_DOWNLOAD=1 NODE_ENV=production pnpm install --frozen-lockfile --prod-only 2>/dev/null || \
       PUPPETEER_SKIP_DOWNLOAD=1 NODE_ENV=production pnpm install --frozen-lockfile

RUN corepack enable pnpm \
    && PUPPETEER_SKIP_DOWNLOAD=1 NODE_OPTIONS="--max-old-space-size=4096" pnpm run build 2>/dev/null || true

# ---------- runtime stage (small) ----------
FROM node:22-slim AS runtime

ENV PNPM_HOME="/pnpm" \
    PATH="$PNPM_HOME:$PATH" \
    NODE_ENV="production"

RUN corepack enable pnpm && groupadd -r dshuser && useradd -r -g dshuser -d /home/dshuser -s /usr/sbin/nologin dshuser

WORKDIR /app

COPY --from=builder --chown=dshuser:dshuser \
    node_modules/ ./node_modules/
COPY --from=builder --chown=dshuser:dshuser \
    lib/           ./lib/
# runtime-only copy: apps/cli built artifacts (the main user-facing entry)
RUN mkdir -p /app/apps/cli/lib && chown dshuser:dshuser /app/apps

# shell capability needs bash for some providers; keep minimal.
COPY --from=builder --chown=dshuser:dshuser \
    packages/shell/lib/ ./packages/shell/lib/ 2>/dev/null || true

RUN corepack enable pnpm && chown -R dshuser:dshuser /app

USER dshuser

# expose default web port (override via docker run for CLI-only)
EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["node", "--eval", "try { require('http').get({host:'localhost',port:process.env.PORT||3001,path:'/healthz'},r=>{if(r.statusCode!==200)process.exit(1)}) }catch(e){process.exit(1)}"]

CMD ["node", "./apps/cli/lib/index.js"]
