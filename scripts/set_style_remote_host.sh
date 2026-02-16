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
ENV_FILE="$ROOT_DIR/.env"
PUBLIC_URL="$SCHEME://$HOST:8081"

if [ ! -f "$STYLE" ]; then
  echo "Style not found: $STYLE" >&2
  exit 1
fi

tmpf="$(mktemp)"
jq --arg u "$PUBLIC_URL/planet.json" '.sources.basemap.url = $u' "$STYLE" > "$tmpf"
mv "$tmpf" "$STYLE"

if [ -f "$ENV_FILE" ]; then
  tmpf="$(mktemp)"
  awk -v v="$PUBLIC_URL" '
    BEGIN { seen=0 }
    /^PMTILES_PUBLIC_URL=/ { print "PMTILES_PUBLIC_URL=" v; seen=1; next }
    { print }
    END { if (seen==0) print "PMTILES_PUBLIC_URL=" v }
  ' "$ENV_FILE" > "$tmpf"
  mv "$tmpf" "$ENV_FILE"
else
  printf 'PMTILES_PUBLIC_URL=%s\n' "$PUBLIC_URL" > "$ENV_FILE"
fi

echo "Updated basemap URL in style: $PUBLIC_URL/planet.json"
echo "Updated PMTILES public URL in .env: $PUBLIC_URL"
echo "Restart tile server to apply: docker compose up -d --force-recreate"
