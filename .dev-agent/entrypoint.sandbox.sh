#!/usr/bin/env bash
# Entrypoint for the musicbox sandbox container.
#
# The root filesystem is read-only at runtime; /home/agent is a tmpfs
# (always empty on start). Flutter's update_engine_version.sh unconditionally
# writes bin/cache/engine.stamp relative to its own location, so /opt/flutter
# must be mirrored into the writable tmpfs before any flutter invocation.
#
# We copy only bin/ (the scripts that derive FLUTTER_ROOT from their own
# path) and symlink everything else (packages, dart SDK artefacts, etc.)
# so the mirror is cheap to create.

set -euo pipefail

mkdir -p /home/agent/flutter
cp -r /opt/flutter/bin /home/agent/flutter/bin
chmod -R u+w /home/agent/flutter/bin/cache

for item in /opt/flutter/*/; do
  name=$(basename "$item")
  [ "$name" = "bin" ] && continue
  ln -sfn "/opt/flutter/$name" "/home/agent/flutter/$name"
done

exec "$@"
