FROM node:24-slim AS builder

# node-pty and koffi compile from source (the patched node-pty ships no
# prebuild), so node-gyp needs a toolchain in the builder.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH" PUPPETEER_SKIP_DOWNLOAD=true CI="true"

WORKDIR /app

RUN corepack enable pnpm \
    && mkdir -p ~/.pnpm-store \
    && echo "storeDir: ~/.pnpm-store" > .npmrc \
    && pnpm config set store-dir ~/.pnpm-store

# Workspace manifests first so the dependency layer stays cacheable and the
# tree is complete: `pnpm run build` then skips its install check.
COPY --link package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY --link patches/ ./patches/
COPY --link scripts/ ./scripts/
COPY --link tsconfig*.json ./
COPY --link packages/*/*/package.json ./packages/
COPY --link vendor/*/package.json ./vendor/
COPY --link native/landlock-run/package.json ./native/landlock-run/
COPY --link native/landlock-run/packages/*/package.json ./native/landlock-run/packages/
COPY --link apps/*/package.json ./apps/
COPY --link website/package.json ./website/
COPY --link examples/package.json ./examples/
COPY --link python/sdk-runtime/package.json ./python/sdk-runtime/

# Dependency layer (lockfile-only): defer lifecycle scripts until the source
# they read (workspace postinstall scripts, node-pty native build) is present.
RUN corepack enable pnpm && pnpm install --frozen-lockfile --ignore-scripts

COPY --link vendor/     ./vendor/
COPY --link packages/   ./packages/
COPY --link native/     ./native/
COPY --link python/     ./python/
COPY --link apps/       ./apps/

# Complete workspace linking and run lifecycle scripts from the cached store:
# node-pty/koffi native builds and the subprocess-local postinstall (the root
# postinstall skips itself via CI=true).
RUN corepack enable pnpm && pnpm install --frozen-lockfile --offline && pnpm rebuild

# build everything (CLI + web) in one pass; we only need the CLI at runtime.
RUN corepack enable pnpm \
    && NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

FROM node:24-slim AS final

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH" PUPPETEER_SKIP_DOWNLOAD=true NODE_ENV="production" DEEPSEEK_API_KEY=""

# node-pty/koffi native addons link libstdc++ at runtime.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable pnpm \
    && groupadd -r dshuser && useradd -r -g dshuser -d /home/dshuser -s /usr/sbin/nologin dshuser

WORKDIR /app

# copy the whole built monorepo so workspace refs resolve correctly.
COPY --from=builder --chown=dshuser:dshuser . ./

USER dshuser

ENTRYPOINT ["pnpm", "dsh"]
