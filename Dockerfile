FROM node:22-slim AS builder

ENV PNPM_HOME="/pnpm" PATH="$PNPM_HOME:$PATH" PUPPETEER_SKIP_DOWNLOAD=true NODE_ENV="production"

WORKDIR /app

RUN corepack enable pnpm \
    && mkdir -p ~/.pnpm-store \
    && echo "storeDir: ~/.pnpm-store" > .npmrc \
    && pnpm config set store-dir ~/.pnpm-store

COPY --link package.json pnpm-workspace.yaml ./
COPY --link tsconfig*.json ./

# cache deps first (lockfile-only layer)
RUN corepack enable pnpm && pnpm install --frozen-lockfile

COPY --link vendor/     ./vendor/
COPY --link packages/   ./packages/
COPY --link native/     ./native/
COPY --link python/     ./python/

# build everything (CLI + web) in one pass; we only need the CLI at runtime.
RUN corepack enable pnpm \
    && NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

FROM node:22-slim AS final

ENV PNPM_HOME="/pnpm" PATH="$PNPM_HOME:$PATH" PUPPETEER_SKIP_DOWNLOAD=true NODE_ENV="production" DEEPSEEK_API_KEY=""

RUN corepack enable pnpm \
    && groupadd -r dshuser && useradd -r -g dshuser -d /home/dshuser -s /usr/sbin/nologin dshuser

WORKDIR /app

# copy the whole built monorepo so workspace refs resolve correctly.
COPY --from=builder --chown=dshuser:dshuser . ./

USER dshuser

ENTRYPOINT ["pnpm", "dsh"]
