#!/usr/bin/env bash
# Build California high-detail vector MBTiles (z0-z15) for extra basemap detail.
#
# Output:
#   data/mbtiles/ca_hi.mbtiles
#
# Source:
#   Geofabrik California extract

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OSM_DIR="${OSM_DIR:-$ROOT_DIR/data/osm}"
MBTILES_DIR="${MBTILES_DIR:-$ROOT_DIR/data/mbtiles}"
TMP_DIR="${TMP_DIR:-$ROOT_DIR/tmp/ca-hi-build}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"

PBF_URL="${PBF_URL:-https://download.geofabrik.de/north-america/us/california-latest.osm.pbf}"
PBF_PATH="$OSM_DIR/california-latest.osm.pbf"
OUT_MB="$MBTILES_DIR/ca_hi.mbtiles"

PLANETILER_IMAGE="${PLANETILER_IMAGE:-openmaptiles/planetiler-openmaptiles:latest}"
MAX_ZOOM="${MAX_ZOOM:-15}"
MIN_ZOOM="${MIN_ZOOM:-0}"
PLANETILER_JAVA_OPTS="${PLANETILER_JAVA_OPTS:--Xmx12g}"
FORCE="${FORCE:-0}"

mkdir -p "$OSM_DIR" "$MBTILES_DIR" "$TMP_DIR" "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/build_ca_hi_vector_${TS}.log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd docker
need_cmd wget

log "Starting California high-zoom vector build."
log "Log file: $LOG_FILE"

if [ ! -s "$PBF_PATH" ]; then
  log "Downloading California OSM extract..."
  wget -c -O "$PBF_PATH" "$PBF_URL" >>"$LOG_FILE" 2>&1
else
  log "Using existing OSM extract: $PBF_PATH"
fi

if [ -s "$OUT_MB" ] && [ "$FORCE" != "1" ]; then
  log "Output already exists, skipping build: $OUT_MB"
  log "Set FORCE=1 to rebuild."
  exit 0
fi

rm -f "$OUT_MB"

log "Running Planetiler in Docker (this may take a while)..."
docker run --rm \
  -e JAVA_TOOL_OPTIONS="$PLANETILER_JAVA_OPTS" \
  -v "$ROOT_DIR/data:/data" \
  -v "$TMP_DIR:/tmp" \
  "$PLANETILER_IMAGE" \
  --download=true \
  --osm-path=/data/osm/california-latest.osm.pbf \
  --output=/data/mbtiles/ca_hi.mbtiles \
  --minzoom="$MIN_ZOOM" \
  --maxzoom="$MAX_ZOOM" \
  --force \
  >>"$LOG_FILE" 2>&1

log "Build complete: $OUT_MB"
