#!/bin/sh
set -eu

DSH_HOME="${DSH_HOME:-/home/dshuser/.dsh}"

# The container starts as root only to hand the mounted data volume to the
# runtime user; the app itself always runs as dshuser. Operators who start the
# container as an unprivileged user skip the handover and run as-is.
if [ "$(id -u)" = "0" ]; then
  mkdir -p "$DSH_HOME"
  chown -R dshuser:dshuser "$DSH_HOME"

  # Seed the NAS defaults on first boot only (written while absent, then left
  # alone): the Web UI binds all interfaces — the CLI --host flag is
  # loopback-only by design — and the /api trust fence accepts the LAN
  # authorities the process derives plus any DSH_TRUSTED_HOSTS. Edit the file
  # to change the bind port or the trusted authorities.
  if [ ! -f "$DSH_HOME/cordis.patch.yml" ]; then
    cat > "$DSH_HOME/cordis.patch.yml" <<'PATCH'
# DeepSeek Harness NAS defaults, seeded on first boot. Edit freely; the
# entrypoint writes this file only while it does not exist.
- id: webserver
  config:
    host: '0.0.0.0'
    port: 3080

- id: connection
  config:
    trustedHosts: !!js (() => [...ctx.webRuntime.trustedHosts, ...(process.env.DSH_TRUSTED_HOSTS ?? '').split(',').map(s => s.trim()).filter(Boolean)])()
PATCH
    chown dshuser:dshuser "$DSH_HOME/cordis.patch.yml"
  fi

  exec setpriv --reuid="$(id -u dshuser)" --regid="$(id -g dshuser)" --init-groups "$@"
fi

exec "$@"
