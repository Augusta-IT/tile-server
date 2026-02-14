#!/usr/bin/env bash
# Set host/IP used by route-planner style for PMTiles basemap (:8081).
# All :8080 style/data/font paths are relative and host-agnostic.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <host_or_ip> [scheme]" >&2
  echo "Example: $0 10.0.0.25 http" >&2
  exit 1
fi

HOST="$1"
SCHEME="${2:-http}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STYLE="$ROOT_DIR/data/styles/route-planner/style.json"

if [ ! -f "$STYLE" ]; then
  echo "Style not found: $STYLE" >&2
  exit 1
fi

tmpf="$(mktemp)"
jq --arg u "$SCHEME://$HOST:8081/planet.json" '.sources.basemap.url = $u' "$STYLE" > "$tmpf"
mv "$tmpf" "$STYLE"

echo "Updated basemap URL in style: $SCHEME://$HOST:8081/planet.json"
echo "Restart tile server to apply: docker compose up -d --force-recreate"
