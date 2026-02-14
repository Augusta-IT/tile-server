#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist}"
TS="$(date +%Y%m%d_%H%M%S)"
BUNDLE_DIR="tile-server-runtime-data_$TS"
STAGE_DIR="$OUT_DIR/$BUNDLE_DIR"
ARCHIVE="$OUT_DIR/$BUNDLE_DIR.tar.gz"

mkdir -p "$OUT_DIR" "$STAGE_DIR/data/mbtiles" "$STAGE_DIR/data/pmtiles" "$STAGE_DIR/data/styles/route-planner"

cp "$ROOT_DIR/data/config.json" "$STAGE_DIR/data/config.json"
cp "$ROOT_DIR/data/styles/route-planner/style.json" "$STAGE_DIR/data/styles/route-planner/style.json"
cp "$ROOT_DIR/docker-compose.yml" "$STAGE_DIR/docker-compose.yml"

cp -a "$ROOT_DIR/data/mbtiles/." "$STAGE_DIR/data/mbtiles/"
cp -a "$ROOT_DIR/data/pmtiles/." "$STAGE_DIR/data/pmtiles/"

(
  cd "$STAGE_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    find . -type f ! -name checksums.sha256 -print0 | xargs -0 sha256sum > checksums.sha256
  else
    find . -type f ! -name checksums.sha256 -print0 | xargs -0 shasum -a 256 > checksums.sha256
  fi
)

(
  cd "$OUT_DIR"
  tar -czf "$ARCHIVE" "$BUNDLE_DIR"
)

rm -rf "$STAGE_DIR"
echo "Created: $ARCHIVE"
