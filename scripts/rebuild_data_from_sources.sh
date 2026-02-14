#!/usr/bin/env bash
# Rebuild runtime tile data from source downloads.
#
# Produces:
# - data/mbtiles/terrain_global_250m.mbtiles
# - data/mbtiles/contours_global_250m.mbtiles
# - data/mbtiles/terrain_ca_uk_hi.mbtiles
# - data/mbtiles/contours_ca_uk_hi.mbtiles
# - data/mbtiles/slope_ca_uk_hi.mbtiles
# - data/mbtiles/ca_hi.mbtiles (unless --skip-ca-vector)
#
# Notes:
# - planet.pmtiles is not downloaded by this script.
#   Provide --planet-pmtiles /path/to/planet.pmtiles to copy it in.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
PMTILES_DIR="${PMTILES_DIR:-$ROOT_DIR/data/pmtiles}"
PLANET_PM_DEST="$PMTILES_DIR/planet.pmtiles"

RUN_DOWNLOAD=1
RUN_BUILD=1
RUN_CA_VECTOR=1
FORCE=0
PLANET_PM_SRC=""

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --download-only             Download raw sources only (no MBTiles build)
  --build-only                Build MBTiles from existing sources only
  --skip-ca-vector            Skip California vector MBTiles build
  --force                     Rebuild outputs even if files already exist
  --planet-pmtiles <path>     Copy existing planet.pmtiles into data/pmtiles/
  -h, --help                  Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --download-only)
      RUN_DOWNLOAD=1
      RUN_BUILD=0
      ;;
    --build-only)
      RUN_DOWNLOAD=0
      RUN_BUILD=1
      ;;
    --skip-ca-vector)
      RUN_CA_VECTOR=0
      ;;
    --force)
      FORCE=1
      ;;
    --planet-pmtiles)
      [ $# -ge 2 ] || { echo "Missing value for --planet-pmtiles" >&2; exit 1; }
      PLANET_PM_SRC="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

mkdir -p "$LOG_DIR" "$PMTILES_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/rebuild_data_from_sources_${TS}.log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd bash

log "Starting source rebuild workflow."
log "Log file: $LOG_FILE"

if [ -n "$PLANET_PM_SRC" ]; then
  if [ ! -s "$PLANET_PM_SRC" ]; then
    echo "Provided --planet-pmtiles does not exist or is empty: $PLANET_PM_SRC" >&2
    exit 1
  fi
  log "Copying planet.pmtiles from: $PLANET_PM_SRC"
  cp -f "$PLANET_PM_SRC" "$PLANET_PM_DEST"
fi

if [ ! -s "$PLANET_PM_DEST" ]; then
  log "planet.pmtiles not found at $PLANET_PM_DEST (this is allowed for build steps, but map basemap will be missing until you copy it)."
fi

if [ "$RUN_DOWNLOAD" -eq 1 ]; then
  need_cmd wget
  need_cmd curl
  log "Downloading DEM source data (global coarse + CA/UK focus)..."
  "$ROOT_DIR/scripts/download_dem_sources_wget.sh" >>"$LOG_FILE" 2>&1
  log "DEM source download step complete."
fi

if [ "$RUN_BUILD" -eq 1 ]; then
  log "Building terrain/contour/slope MBTiles..."
  FORCE="$FORCE" "$ROOT_DIR/scripts/build_terrain_mbtiles.sh" >>"$LOG_FILE" 2>&1
  log "Terrain/contour/slope build complete."

  if [ "$RUN_CA_VECTOR" -eq 1 ]; then
    need_cmd docker
    log "Building California vector MBTiles..."
    FORCE="$FORCE" "$ROOT_DIR/scripts/build_ca_hi_vector_mbtiles.sh" >>"$LOG_FILE" 2>&1
    log "California vector build complete."
  else
    log "Skipping California vector build."
  fi
fi

log "Validating expected outputs..."
required_outputs=(
  "$ROOT_DIR/data/mbtiles/terrain_global_250m.mbtiles"
  "$ROOT_DIR/data/mbtiles/contours_global_250m.mbtiles"
  "$ROOT_DIR/data/mbtiles/terrain_ca_uk_hi.mbtiles"
  "$ROOT_DIR/data/mbtiles/contours_ca_uk_hi.mbtiles"
  "$ROOT_DIR/data/mbtiles/slope_ca_uk_hi.mbtiles"
)
if [ "$RUN_CA_VECTOR" -eq 1 ] && [ "$RUN_BUILD" -eq 1 ]; then
  required_outputs+=("$ROOT_DIR/data/mbtiles/ca_hi.mbtiles")
fi

for f in "${required_outputs[@]}"; do
  if [ ! -s "$f" ]; then
    echo "Missing expected output: $f" >&2
    exit 1
  fi
done

log "Workflow complete."
if [ -s "$PLANET_PM_DEST" ]; then
  log "Basemap PMTiles present: $PLANET_PM_DEST"
else
  log "Basemap PMTiles missing: copy planet.pmtiles to $PLANET_PM_DEST before running the map."
fi
log "Done."
