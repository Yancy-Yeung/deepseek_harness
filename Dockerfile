FROM node:24-slim AS builder

# node-pty and koffi compile from source (the patched node-pty ships no
# prebuild), so node-gyp needs a toolchain in the builder.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH" PUPPETEER_SKIP_DOWNLOAD=true CI="true"

WORKDIR /app

RUN corepack enable pnpm

# Single install over the full source tree. The two-phase lockfile-only layer
# failed here: the second, --offline pass had to add 349 packages and fetch a
# tarball the first install never downloaded, so the manifest-only tree was
# not trustworthy. Install is fast (~7s), so the caching win is not worth
# the fragility.
COPY . .

RUN corepack enable pnpm \
    && pnpm install --frozen-lockfile

# build everything (CLI + web) in one pass; we only need the CLI at runtime.
RUN corepack enable pnpm \
    && NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

FROM node:24-slim AS final

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH" PUPPETEER_SKIP_DOWNLOAD=true NODE_ENV="production"

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
