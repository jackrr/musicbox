#!/usr/bin/env bash
# Entrypoint for the musicbox sandbox container.
#
# The root filesystem is read-only at runtime; /home/agent is a tmpfs
# (always empty on start). Flutter's update_engine_version.sh unconditionally
# writes bin/cache/engine.stamp relative to its own location, so /opt/flutter
# must be mirrored into the writable tmpfs before any flutter invocation.
#
# We symlink most of the tree and only copy the small stamp files in
# bin/cache/ that Flutter unconditionally writes to. Large cached
# artefacts (dart-sdk, engine, etc.) stay as symlinks to /opt/flutter.

set -euo pipefail

echo "[entrypoint] starting ($(date -Is))" >&2

# Mirror /opt/flutter into the writable tmpfs at /home/agent/flutter.
# Strategy: symlink everything *except* bin/cache, which Flutter writes to
# (stamp files like engine.stamp, flutter_tools.stamp). Large subdirs inside
# bin/cache/ (dart-sdk, artifacts, …) are read-only after precache, so we
# symlink those too. Only small stamp/config files get copied.
#
# This keeps tmpfs usage to kilobytes instead of the hundreds of MB that a
# naive `cp -r /opt/flutter/bin` would require.

mkdir -p /home/agent/flutter/bin

# Symlink top-level items in bin/ except cache/
for item in /opt/flutter/bin/*; do
  name=$(basename "$item")
  [ "$name" = "cache" ] && continue
  ln -sfn "$item" "/home/agent/flutter/bin/$name"
done

# Create bin/cache as a real directory; symlink subdirs, copy files (stamps)
mkdir -p /home/agent/flutter/bin/cache
for item in /opt/flutter/bin/cache/*; do
  [ ! -e "$item" ] && continue
  name=$(basename "$item")
  if [ -d "$item" ]; then
    ln -sfn "$item" "/home/agent/flutter/bin/cache/$name"
  else
    cp "$item" "/home/agent/flutter/bin/cache/$name"
  fi
done

# Symlink remaining top-level flutter directories (packages, etc.)
for item in /opt/flutter/*/; do
  name=$(basename "$item")
  [ "$name" = "bin" ] && continue
  ln -sfn "/opt/flutter/$name" "/home/agent/flutter/$name"
done

echo "[entrypoint] flutter mirror ready ($(du -sh /home/agent/flutter 2>/dev/null | cut -f1))" >&2
echo "[entrypoint] tmpfs usage: $(df -h /home/agent 2>/dev/null | tail -1)" >&2
echo "[entrypoint] exec: $*" >&2

# PATH for docker exec sessions is set via /etc/profile.d/toolchain.sh (login shells)
# and via ENV in the Dockerfile (non-login shells). No export needed here.
exec "$@"
