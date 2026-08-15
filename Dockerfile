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

# The runtime does not run pnpm on the default path: the image already
# contains a fresh install, and pnpm's start-time dependency check would
# re-run install — and fail — in a read-only deployment. The npm_config_* and
# corepack settings only matter when an operator overrides the command to use
# pnpm (e.g. `dsh plugin`), which is why the corepack cache is pre-warmed
# below.
ENV NODE_ENV="production" \
    PUPPETEER_SKIP_DOWNLOAD=true \
    DSH_HOME="/home/dshuser/.dsh" \
    PNPM_HOME="/pnpm" \
    PATH="$PNPM_HOME:$PATH" \
    npm_config_verify_deps_before_run=false \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# node-pty/koffi native addons link libstdc++ at runtime.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# dshuser owns the harness home (sessions, settings, credentials, profiles)
# and the /app workspace the agent works in. The entrypoint runs as root only
# to fix the mounted volume's ownership, then drops to this user.
RUN corepack enable pnpm \
    && groupadd -r dshuser \
    && useradd -r -g dshuser -d /home/dshuser -s /usr/sbin/nologin dshuser \
    && mkdir -p /home/dshuser/.dsh /home/dshuser/.cache/node/corepack \
    && chown -R dshuser:dshuser /home/dshuser

WORKDIR /app

# Copy the built monorepo from the builder. The builder's WORKDIR is /app,
# so we copy from /app there, not from /.
COPY --from=builder --chown=dshuser:dshuser /app .

# COPY --chown does not change the ownership of a destination directory that
# already exists (WORKDIR created /app as root); the agent's tools write into
# the /app workspace, so hand the whole tree to the runtime user.
RUN chown -R dshuser:dshuser /app

# Pre-warm the corepack pnpm cache as dshuser so an overridden pnpm command
# never downloads pnpm on first use (the NAS may be offline).
USER dshuser
RUN corepack prepare "$(node -e 'console.log(require(process.argv[1]).packageManager)' /app/package.json)" --activate
USER root

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# The entrypoint fixes the mounted $DSH_HOME volume's ownership and seeds the
# NAS LAN-bind defaults on first boot, then drops to dshuser. The default
# command runs the built CLI in web mode (the NAS appliance); override CMD for
# other profiles, e.g. ["node", "apps/cli/lib/bin.js", "task"].
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "apps/cli/lib/bin.js", "web"]
